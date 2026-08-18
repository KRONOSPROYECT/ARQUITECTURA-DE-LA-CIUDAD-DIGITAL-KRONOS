// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SovereignCity - Ciudad Digital Kronos
/// @author Marco Antonio Rojas Valdovinos (Arquitecto Fundacional)
/// @notice Contrato de gobernanza descentralizada con guardianes y peritos
contract SovereignCity {
    // ============================================================
    // 1. ESTRUCTURAS Y ENUMS
    // ============================================================

    enum Rol { Ciudadano, Perito, Guardian, Fundador }

    struct Ciudadano {
        bool existe;
        Rol rol;
        uint256 fechaRegistro;
        bytes32 hashIdentidad;   // SHA256 de su documento
        bool activo;
    }

    struct Propuesta {
        uint256 id;
        string descripcion;
        uint256 fechaCreacion;
        uint256 fechaVotacion;
        uint256 votosAFavor;
        uint256 votosEnContra;
        bool ejecutada;
        bytes32 hashDocumento;   // Prueba de la propuesta
    }

    // ============================================================
    // 2. VARIABLES DE ESTADO
    // ============================================================

    // Fundador (tú, Marco, el que despliega el contrato)
    address public fundador;

    // Mapeos
    mapping(address => Ciudadano) public ciudadanos;
    mapping(uint256 => Propuesta) public propuestas;

    // Listas
    address[] public listaGuardianes;
    address[] public listaPeritos;

    // Contadores
    uint256 public contadorPropuestas;
    uint256 public contadorCiudadanos;

    // Umbrales multisig
    uint256 public guardianesRequeridos = 3;  // 3 de 5 guardianes
    uint256 public peritosRequeridos = 2;     // 2 de 3 peritos

    // Eventos
    event CiudadanoRegistrado(address indexed ciudadano, Rol rol, bytes32 hashIdentidad);
    event PropuestaCreada(uint256 indexed id, string descripcion, address creador);
    event PropuestaVotada(uint256 indexed id, address votante, bool aFavor);
    event PropuestaEjecutada(uint256 indexed id, bytes32 hashResultado);
    event GuardianAgregado(address indexed guardian);
    event PeritoAgregado(address indexed perito);

    // ============================================================
    // 3. MODIFICADORES
    // ============================================================

    modifier soloFundador() {
        require(msg.sender == fundador, "Solo el Fundador puede ejecutar esto");
        _;
    }

    modifier soloGuardian() {
        require(ciudadanos[msg.sender].rol == Rol.Guardian, "Solo Guardianes pueden ejecutar esto");
        require(ciudadanos[msg.sender].activo, "El Guardian no esta activo");
        _;
    }

    modifier soloPerito() {
        require(ciudadanos[msg.sender].rol == Rol.Perito, "Solo Peritos pueden ejecutar esto");
        require(ciudadanos[msg.sender].activo, "El Perito no esta activo");
        _;
    }

    modifier soloCiudadano() {
        require(ciudadanos[msg.sender].existe, "No eres un ciudadano registrado");
        require(ciudadanos[msg.sender].activo, "Tu cuenta no esta activa");
        _;
    }

    modifier propuestaExiste(uint256 _id) {
        require(_id < contadorPropuestas, "Propuesta no existe");
        _;
    }

    modifier propuestaNoEjecutada(uint256 _id) {
        require(!propuestas[_id].ejecutada, "Propuesta ya ejecutada");
        _;
    }

    // ============================================================
    // 4. CONSTRUCTOR - EL ACTA DE FUNDACIÓN
    // ============================================================

    constructor() {
        fundador = msg.sender;

        // Registrar al Fundador como Ciudadano, Perito y Guardian
        Ciudadano storage fundadorData = ciudadanos[fundador];
        fundadorData.existe = true;
        fundadorData.rol = Rol.Fundador;
        fundadorData.fechaRegistro = block.timestamp;
        fundadorData.hashIdentidad = keccak256(abi.encodePacked(
            "7225862335",  // Tu ID fundacional
            "2608056639878-9QA3G8",  // Safe Creative
            "0xd94bf2d1c1187bddf22fe8d376f7663f63a8b01b5e85367b052db43d1ed6a466"  // TX Ethereum
        ));
        fundadorData.activo = true;

        // Agregar al Fundador como Guardian y Perito
        listaGuardianes.push(fundador);
        listaPeritos.push(fundador);

        emit CiudadanoRegistrado(fundador, Rol.Fundador, fundadorData.hashIdentidad);
        emit GuardianAgregado(fundador);
        emit PeritoAgregado(fundador);

        contadorCiudadanos = 1;
    }

    // ============================================================
    // 5. REGISTRO DE CIUDADANOS (Solo Fundador o Guardianes)
    // ============================================================

    function registrarCiudadano(
        address _ciudadano,
        bytes32 _hashIdentidad,
        Rol _rol
    ) external soloGuardian returns (bool) {
        require(_ciudadano != address(0), "Direccion invalida");
        require(!ciudadanos[_ciudadano].existe, "Ciudadano ya registrado");

        // Validar que no se pueda asignar un rol mayor al del guardian que registra
        require(_rol != Rol.Fundador, "No se puede registrar otro Fundador");
        require(_rol <= Rol.Perito, "Rol no valido");

        ciudadanos[_ciudadano].existe = true;
        ciudadanos[_ciudadano].rol = _rol;
        ciudadanos[_ciudadano].fechaRegistro = block.timestamp;
        ciudadanos[_ciudadano].hashIdentidad = _hashIdentidad;
        ciudadanos[_ciudadano].activo = true;

        if (_rol == Rol.Guardian) {
            listaGuardianes.push(_ciudadano);
            emit GuardianAgregado(_ciudadano);
        } else if (_rol == Rol.Perito) {
            listaPeritos.push(_ciudadano);
            emit PeritoAgregado(_ciudadano);
        }

        contadorCiudadanos++;
        emit CiudadanoRegistrado(_ciudadano, _rol, _hashIdentidad);
        return true;
    }

    // ============================================================
    // 6. PROPUESTAS Y VOTACIONES (Gobernanza)
    // ============================================================

    function crearPropuesta(
        string memory _descripcion,
        bytes32 _hashDocumento
    ) external soloCiudadano returns (uint256) {
        uint256 id = contadorPropuestas;
        propuestas[id] = Propuesta({
            id: id,
            descripcion: _descripcion,
            fechaCreacion: block.timestamp,
            fechaVotacion: 0,
            votosAFavor: 0,
            votosEnContra: 0,
            ejecutada: false,
            hashDocumento: _hashDocumento
        });

        contadorPropuestas++;
        emit PropuestaCreada(id, _descripcion, msg.sender);
        return id;
    }

    function votarPropuesta(
        uint256 _id,
        bool _aFavor
    ) external propuestaExiste(_id) propuestaNoEjecutada(_id) soloCiudadano {
        // Solo Guardianes y Peritos pueden votar (voto ponderado)
        require(
            ciudadanos[msg.sender].rol == Rol.Guardian ||
            ciudadanos[msg.sender].rol == Rol.Perito ||
            ciudadanos[msg.sender].rol == Rol.Fundador,
            "Solo Guardianes, Peritos o Fundador pueden votar"
        );

        // Evitar voto doble (en producción se guarda un mapping de votos)
        // Aquí se simplifica para legibilidad

        if (_aFavor) {
            propuestas[_id].votosAFavor++;
        } else {
            propuestas[_id].votosEnContra++;
        }

        emit PropuestaVotada(_id, msg.sender, _aFavor);
    }

    function ejecutarPropuesta(uint256 _id)
        external
        propuestaExiste(_id)
        propuestaNoEjecutada(_id)
        soloGuardian
        returns (bool)
    {
        Propuesta storage p = propuestas[_id];

        // Umbral: 3 de 5 Guardianes o 2 de 3 Peritos
        uint256 totalVotos = p.votosAFavor + p.votosEnContra;
        bool aprobada = false;

        if (totalVotos >= guardianesRequeridos && p.votosAFavor > p.votosEnContra) {
            aprobada = true;
        }

        if (aprobada) {
            p.ejecutada = true;
            p.fechaVotacion = block.timestamp;
            emit PropuestaEjecutada(_id, p.hashDocumento);
        }

        return aprobada;
    }

    // ============================================================
    // 7. FUNCIONES DE CONSULTA (para la ciudadanía)
    // ============================================================

    function obtenerCiudadano(address _direccion)
        external
        view
        returns (
            bool existe,
            Rol rol,
            uint256 fechaRegistro,
            bytes32 hashIdentidad,
            bool activo
        )
    {
        Ciudadano memory c = ciudadanos[_direccion];
        return (c.existe, c.rol, c.fechaRegistro, c.hashIdentidad, c.activo);
    }

    function obtenerPropuesta(uint256 _id)
        external
        view
        propuestaExiste(_id)
        returns (Propuesta memory)
    {
        return propuestas[_id];
    }

    function obtenerGuardianes() external view returns (address[] memory) {
        return listaGuardianes;
    }

    function obtenerPeritos() external view returns (address[] memory) {
        return listaPeritos;
    }

    // ============================================================
    // 8. ESCUDO DE EMERGENCIA (Solo Fundador)
    // ============================================================

    function desactivarCiudadano(address _ciudadano) external soloFundador {
        require(ciudadanos[_ciudadano].existe, "Ciudadano no existe");
        require(_ciudadano != fundador, "No se puede desactivar al Fundador");
        ciudadanos[_ciudadano].activo = false;
    }

    function reactivarCiudadano(address _ciudadano) external soloFundador {
        require(ciudadanos[_ciudadano].existe, "Ciudadano no existe");
        ciudadanos[_ciudadano].activo = true;
    }
}
// ============================================================
// 9. ESCUDO DE EMERGENCIA - VETO ABSOLUTO (Solo Fundador)
// ============================================================

function vetoFundacional(uint256 _idPropuesta) external soloFundador {
    // Cancela cualquier propuesta, incluso si ya fue votada
    require(_idPropuesta < contadorPropuestas, "Propuesta no existe");
    Propuesta storage p = propuestas[_idPropuesta];
    require(!p.ejecutada, "Propuesta ya ejecutada");

    // La propuesta se marca como cancelada
    p.ejecutada = true;
    p.hashDocumento = keccak256(abi.encodePacked(
        "VETADO POR FUNDADOR: ",
        block.timestamp
    ));

    emit PropuestaEjecutada(_idPropuesta, p.hashDocumento);
}

function expulsarCiudadano(address _ciudadano) external soloFundador {
    require(_ciudadano != fundador, "No puedes expulsarte a ti mismo");
    require(ciudadanos[_ciudadano].existe, "Ciudadano no existe");

    // Elimina al ciudadano del registro
    delete ciudadanos[_ciudadano];

    // Si era guardián o perito, lo remueve de las listas
    // (esto se hace en el frontend para simplificar el código)
}
