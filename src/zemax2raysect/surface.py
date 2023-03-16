"""Surface classes that represent OpticsStudio Surface Types."""
from dataclasses import dataclass, field
from typing import Dict, Sequence, Tuple

from raysect.core import AffineMatrix3D, rotate_x, rotate_y, rotate_z, translate


@dataclass
class SurfaceDescription:
    """Dataclass holding a surface description from a ZMX-file.

    Note:
        LDE is the Lens Data Editor in Zemax OpticsStudio.

    Parameters
    ----------
    n : int, default = -1
        Surface number.
    name : str, default = ""
        Surface's name. "Comment" in LDE.
    type : str, default = ""
        Type of the surface. Surface Type in LDE.
    curv : float, default = 0
        Surface's curvature. Reciprocal of "Radius" in LDE. "Infinity" stored as 0.
    disz : float, default = 0
        Surface's thickness. "Thickness" in LDE. Infinite thickness is not supported.
    glas : str, default = ""
        Surface's material. "Glass" in LDE.
    diam : float, default = 0
        Surface's radius. "Semi-Diameter" in LDE.
    sqap : (float, float), default = None
        Surface's aperture width in x and y directions.
    obdc : (float, float), default = None
        Surface's aperture decenter in x and y directions.
    parm : dict(int, float), default = {}
        Dictionary of additional surface parameters. Contents depend on surface type.

    Methods
    -------
    fromlines(lines : sequence of str) : SurfaceDescription
        Build a SurfaceDescription from a sequence of text lines.
    """

    n: int = -1
    name: str = ""
    type: str = ""
    curv: float = 0.0
    disz: float = 0.0
    glas: str = ""
    diam: float = 0.0
    sqap: Tuple[float, float] = None
    obdc: Tuple[float, float] = None
    parm: Dict[int, float] = field(default_factory=dict)

    @staticmethod
    def fromlines(lines: Sequence[str]) -> "SurfaceDescription":
        """Build a SurfaceDescription instance from a sequence of text lines.

        Interprets the text block from a ZMX-file starting from "SURF #" until the next surface.

        Parameters
        ----------
        lines : sequence of str

        Returns
        -------
        SurfaceDescription
        """
        description = SurfaceDescription()
        next_description = False

        for _, line in enumerate(lines):

            columns = line.strip().split()
            if len(columns) < 2:
                continue

            cmd = columns[0]
            value = columns[1]

            # surface number
            if cmd == "SURF":
                if not next_description:
                    description.n = int(value)
                    next_description = True
                else:
                    return description

            # Comment
            if cmd == "COMM":
                description.name = value

            # Surface Type
            if cmd == "TYPE":
                description.type = value

            # 1 / Radius
            if cmd == "CURV":
                description.curv = float(value)

            # Thickness
            if cmd == "DISZ":
                description.disz = float(value)

            # Glass
            if cmd == "GLAS":
                description.glas = value

            # Semi-Diameter
            if cmd == "DIAM":
                description.diam = float(value)

            # Aperture
            if cmd == "SQAP":
                description.sqap = (float(columns[1]), float(columns[2]))

            # Aperture decenter
            if cmd == "OBDC":
                description.obdc = (float(columns[1]), float(columns[2]))

            # Parameters
            if cmd == "PARM":
                description.parm[int(columns[1])] = float(columns[2])

        return description


@dataclass
class Surface:
    """Base class for the representation of OpticsStudio surface.

    Parameters
    ----------
    name : str, default = ""
        Surface's name.
    radius : float, default = 0
        Curvature radius. 0 represents infinite radius.
    thickness : float, default = 0
        Surface's thickness. Infinite thickness is not supported.
    material : str, default = ""
        Surface's material.
    semi_diameter : float, default = 0
        Surface's semi-diameter.
    aperture : (float, float), default = None
        Aperture width in x and y directions.
    aperture_decenter : (float, float), default = None
        Aperture decenter in x and y directions.

    Methods
    -------
    create(description: SurfaceDescription, units_factor: float = 1.0) : Surface
        Create new Surface instance from SurfaceDescription.
    """

    name: str = ""
    radius: float = 0
    thickness: float = 0.0
    material: str = ""
    semi_diameter: float = 0.0
    aperture: Tuple[float, float] = None
    aperture_decenter: Tuple[float, float] = None

    @staticmethod
    def create(description: SurfaceDescription, units_factor: float = 1.0) -> "Surface":
        """Create new Surface instance from SurfaceDescription.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        Surface
        """
        raise NotImplementedError


class SurfaceBuilder:
    """Surface builder class.

    Parameters
    cls : Surface
        Subclass of surface to build.

    Methods
    -------
    build(description: SurfaceDescription, units_factor: float = 1.0) : Surface
        Build a new instance of Surface subclass using SurfaceDescription.
    """

    def __init__(self, cls: Surface) -> None:
        """Initialize a new builder for a particular subclass of Surface.

        Parameters
        ----------
        cls : Surface
            Subclass of Surface.

        Returns
        -------
        None
        """
        self.cls = cls

    def build(self, description: SurfaceDescription, units_factor: float = 1.0) -> Surface:
        """Build a new instance of Surface subclass using SurfaceDescription.

        Initializes attributes common for most surface types.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        surface : subclass of Surface
        """
        obj = self.cls()
        obj.name = description.name

        if description.curv != 0:
            obj.radius = 1 / description.curv * units_factor

        obj.thickness = description.disz * units_factor
        obj.semi_diameter = description.diam * units_factor
        obj.material = description.glas

        if description.sqap is not None:
            obj.aperture = (description.sqap[0] * units_factor, description.sqap[1] * units_factor)

        if description.obdc is not None:
            obj.aperture_decenter = (
                description.obdc[0] * units_factor,
                description.obdc[1] * units_factor,
            )

        return obj


@dataclass
class CoordinateBreak(Surface):
    """Class representing Coordinate Break surface.

    Below are parameters additional to the Surface superclass.

    Parameters
    ----------
    decenter_x : float, default = 0
        Translation along x axis.
    decenter_y : float, default = 0
        Translation along y axis.
    tilt_x : float, default = 0
        Rotation around x axis in degrees.
    tilt_y : float, default = 0
        Rotation around y axis in degrees.
    tilt_z : float, default = 0
        Rotation around z axis in degrees.

    Attributes
    ----------
    matrix : AffineMatrix3D
        Return transformation matrix appropriate to this Coordinate Break.
        Translation along z axis appropriate to the thickness is not applied.

    Methods
    -------
    create(description: SurfaceDescription, units_factor: float = 1.0) : Surface
        Build a new instance of CoordinateBreak using SurfaceDescription.
    """

    decenter_x: float = 0.0
    decenter_y: float = 0.0

    tilt_x: float = 0.0
    tilt_y: float = 0.0
    tilt_z: float = 0.0

    @property
    def matrix(self) -> AffineMatrix3D:
        """Return transformation matrix appropriate to this Coordinate Break.

        Translation along z axis appropriate to the thickness is not applied.

        Returns
        -------
        AffineMatrix3D
        """
        return (
            translate(self.decenter_x, self.decenter_y, 0)
            * rotate_x(self.tilt_x)
            * rotate_y(self.tilt_y)
            * rotate_z(self.tilt_z)
        )

    @staticmethod
    def create(description: SurfaceDescription, units_factor: float = 1.0) -> "CoordinateBreak":
        """Build a new instance of CoordinateBreak using SurfaceDescription.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        surface : CoordinateBreak
        """
        if description.type != "COORDBRK":
            raise ValueError(f"Expected description.type 'COORDBRK', got {description.type}")

        if len(description.parm) < 5:
            raise IndexError("Not enough parameters to define a coordiante break")

        params = description.parm

        return CoordinateBreak(
            thickness=description.disz * units_factor,
            decenter_x=params[1] * units_factor,
            decenter_y=params[2] * units_factor,
            tilt_x=params[3],
            tilt_y=params[4],
            tilt_z=params[5],
        )


@dataclass
class Standard(Surface):
    """Class representing Standard type surface.

    Methods
    -------
    create(description: SurfaceDescription, units_factor: float = 1.0) : Surface
        Build a new instance of Standard using SurfaceDescription.
    """

    @staticmethod
    def create(description: SurfaceDescription, units_factor: float = 1) -> "Surface":
        """Build a new instance of Standard using SurfaceDescription.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        Standard
        """
        if description.type != "STANDARD":
            raise ValueError(f"Expected type 'STANDARD', got {description.type}")

        return SurfaceBuilder(Standard).build(description, units_factor)


@dataclass
class Tilted(Surface):
    """Class representing Tilted type surface.

    Parameters
    ----------
    tan_x : float, default = 0
        Tangent of the angle between the plane and x axis.
    tan_y : float, default = 0
        Tangent of the angle between the plane and y axis.

    Methods
    -------
    create(description: SurfaceDescription, units_factor: float = 1.0) : Surface
        Build a new instance of Tilted using SurfaceDescription.
    """

    tan_x: float = 0.0
    tan_y: float = 0.0

    @staticmethod
    def create(description: SurfaceDescription, units_factor: float = 1.0) -> "Tilted":
        """Build a new instance of Tilted using SurfaceDescription.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        Tilted
        """
        if description.type != "TILTSURF":
            raise ValueError(f"Expected description.type 'TILTSURF', got {description.type}")

        if len(description.parm) != 2:
            raise IndexError(
                f"Expected description.parm to have exactly 2 items, got {len(description.parm)}"
            )

        obj = SurfaceBuilder(Tilted).build(description, units_factor)

        obj.tan_x = description.parm[1]
        obj.tan_y = description.parm[2]

        return obj


@dataclass
class Toroidal(Surface):
    """Class representing Toroidal type surface.

    Parameters
    ----------
    radius_horizontal : float, default = 0
        Curvature radius in x-z plane.

    Methods
    -------
    create(description: SurfaceDescription, units_factor: float = 1.0) : Surface
        Build a new instance of Toroidal using SurfaceDescription.
    """

    radius_horizontal: float = 0.0

    @staticmethod
    def create(description: SurfaceDescription, units_factor: float = 1.0) -> "Toroidal":
        """Build a new instance of Toroidal using SurfaceDescription.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        Toroidal
        """
        if description.type not in ("TOROIDAL", "BICONICX"):
            raise ValueError(
                f"Expected description.type 'TOROIDAL' or 'BICONICX', got {description.type}"
            )

        if len(description.parm) < 2:
            raise ValueError(
                f"Expected description.parm to have at least 2 items, got {len(description.parm)}"
            )

        obj = SurfaceBuilder(Toroidal).build(description, units_factor)
        obj.radius_horizontal = description.parm[1] * units_factor

        return obj


class AbstractSurfaceBuilder:
    """Abstract builder class for all implemented surfaces.

    Parameters
    ----------
    builders : dict(str, Surface)
        Dictionary which maps surface types from a ZMX-file to Surface subclasses.
    """

    builders: Dict[str, Surface] = {
        "COORDBRK": CoordinateBreak,
        "STANDARD": Standard,
        "TOROIDAL": Toroidal,
        "BICONICX": Toroidal,
        "TILTSURF": Tilted,
    }

    def create(self, description: SurfaceDescription, units_factor: float = 1.0) -> Surface:
        """Build a new instance of Surface subclass using SurfaceDescription.

        Parameters
        ----------
        description : SurfaceDescription
        units_factor : float, default = 1
            Units conversion factor.

        Returns
        -------
        Surface
        """
        if description.type not in self.builders:
            raise RuntimeError(f"Surface type {description.type} is not implemented")

        builder = self.builders[description.type]

        return builder.create(description, units_factor)
