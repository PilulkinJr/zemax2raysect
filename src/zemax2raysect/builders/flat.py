"""Builder classes for two surface flat optical elements."""
import logging
from typing import Dict, Union

from raysect.core import Material, Point3D
from raysect.primitive import Box, Cylinder

from ..materials import find_material
from ..surface import Standard, Toroidal
from .base import MirrorBuilder
from .common import (
    DEFAULT_THICKNESS,
    CannotCreatePrimitive,
    Direction,
    ShapeType,
    SurfaceType,
    determine_primitive_type,
)

LOGGER = logging.getLogger(__name__)


class CylinderBuilder(MirrorBuilder):
    """Builder class for cylinder-shaped optical elements."""

    def __init__(self: "CylinderBuilder") -> None:
        """Initializes a new instance of CylinderBuilder and a set of parameters.

        Returns
        -------
        None
        """
        self._clear_parameters()

    def _clear_parameters(self: "CylinderBuilder") -> None:
        """Initialize a set of parameters.

        Returns
        -------
        None
        """
        self._radius: float = None
        self._thickness: float = None
        self._material: Material = None
        self._name: str = None

    def _extract_parameters(
        self: "CylinderBuilder",
        surface: Union[Standard, Toroidal],
    ) -> None:
        """Extract parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal

        Returns
        -------
        None
        """
        if surface.semi_diameter < 1e-8:
            raise CannotCreatePrimitive(
                f"Cannot create Cylinder from {surface}: radius is too small: {surface.radius}"
            )

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type is not SurfaceType.FLAT:
            raise CannotCreatePrimitive(f"Cannot create Cylinder from {surface}: it is not flat")

        if shape_type is not ShapeType.ROUND:
            raise CannotCreatePrimitive(f"Cannot create Cylinder from {surface}: it is not round")

        self._radius = surface.semi_diameter
        self._thickness = surface.thickness or DEFAULT_THICKNESS
        self._material = find_material(surface.material)
        self._name = surface.name

    def build(
        self: "CylinderBuilder",
        surface: Union[Standard, Toroidal],
        direction: Direction = 1,
    ) -> Cylinder:
        """Create a raysect.primitive.Cylinder using parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal

        Returns
        -------
        Cylinder
        """
        self._clear_parameters()
        self._extract_parameters(surface)

        return Cylinder(self._radius, self._thickness, material=self._material, name=self._name)


class BoxBuilder(MirrorBuilder):
    def __init__(self: "BoxBuilder") -> None:
        """Initializes a new instance of BoxBuilder and a set of parameters.

        Returns
        -------
        None
        """
        self._clear_parameters()

    def _clear_parameters(self: "BoxBuilder") -> None:
        """Initialize a set of parameters.

        Returns
        -------
        None
        """
        self._semi_width: float = None
        self._semi_height: float = None
        self._thickness: float = None
        self._material: Material = None
        self._name: str = None

    def _extract_parameters(
        self: "BoxBuilder",
        surface: Union[Standard, Toroidal],
    ) -> None:
        """Extract parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal

        Returns
        -------
        None
        """
        if surface.semi_diameter < 1e-8:
            raise CannotCreatePrimitive(
                f"Cannot create Cylinder from {surface}: radius is too small: {surface.radius}"
            )

        if surface.aperture is None:
            raise CannotCreatePrimitive(
                f"Cannot create a box-shaped object from {surface}: aperture dimensions is not set"
            )

        if surface.aperture_decenter is not None:
            raise CannotCreatePrimitive(
                f"Cannot create a box-shaped object from {surface}: "
                "aperture decenter is not implemented"
            )

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type is not SurfaceType.FLAT:
            raise CannotCreatePrimitive(f"Cannot create Box from {surface}: it is not flat")

        if shape_type is not ShapeType.RECTANGULAR:
            raise CannotCreatePrimitive(f"Cannot create Box from {surface}: it is not rectangular")

        self._semi_width = surface.aperture[0]
        self._semi_height = surface.aperture[1]
        self._thickness = surface.thickness or DEFAULT_THICKNESS
        self._material = find_material(surface.material)
        self._name = surface.name

    def build(
        self: "BoxBuilder",
        surface: Union[Standard, Toroidal],
        direction: Direction,
    ) -> Box:
        """Create a raysect.primitive.Box using parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal

        Returns
        -------
        Box
        """
        self._clear_parameters()
        self._extract_parameters(surface)

        lower = Point3D(-self._semi_width, -self._semi_height, 0)
        upper = Point3D(self._semi_width, self._semi_height, self._thickness)

        return Box(lower, upper, material=self._material, name=self._name)


class AbstractFlatPrimitiveBuilder:
    """Abstract builder class for flat primitives."""

    builders: Dict[str, MirrorBuilder] = {
        "cylinder": CylinderBuilder,
        "box": BoxBuilder,
    }

    @classmethod
    def get_builder(cls: "AbstractFlatPrimitiveBuilder", name: str) -> MirrorBuilder:
        """Return a builder for a primitive with a requested name.

        Parameters
        ----------
        name : str

        Returns
        -------
        MirrorBuilder
        """
        if name not in cls.builders:
            msg = (
                f"Builder for '{name}' flat mirror is not implemented"
                f", try one of {tuple(name for name in cls.builders)}"
            )
            raise KeyError(msg)

        return cls.builders[name]

    @classmethod
    def build(
        cls: "AbstractFlatPrimitiveBuilder",
        name: str,
        surface: Union[Standard, Toroidal],
        direction: Direction = 1,
    ) -> Union[Cylinder, Box]:
        """Build a primitive with a requested name.

        Parameters
        ----------
        name : str
        surface : Standard or Toroidal
        direction : {-1, 1}, default = 1

        Returns
        -------
        Circle or Rectangle
        """
        return cls.get_builder(name)().build(surface, direction)


def create_cylinder(surface: Union[Standard, Toroidal], direction: Direction = 1) -> Cylinder:
    return CylinderBuilder().build(surface, direction)


def create_box(surface: Union[Standard, Toroidal], direction: Direction = 1) -> Box:
    return BoxBuilder().build(surface, direction)
