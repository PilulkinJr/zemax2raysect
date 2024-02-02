"""Builder classes for single surface type elements."""
import logging
from typing import Dict, Union

from raysect.core import Material

from ..materials import find_material
from ..primitive.surface.circle import Circle
from ..primitive.surface.rectangle import Rectangle
from ..surface import Standard, Toroidal
from .base import MirrorBuilder
from .common import (
    CannotCreatePrimitive,
    Direction,
    ShapeType,
    SurfaceType,
    determine_primitive_type,
)

LOGGER = logging.getLogger(__name__)


class CircleBuilder(MirrorBuilder):
    """Builder class for flat circle type surfaces."""

    def __init__(self: "CircleBuilder") -> None:
        """Initializes a new instance of CircleBuilder and a set of parameters.

        Returns
        -------
        None
        """
        self._clear_parameters()

    def _clear_parameters(self: "CircleBuilder") -> None:
        """Initialize a set of parameters.

        Returns
        -------
        None
        """
        self._radius: float = None
        self._material: Material = None
        self._name: str = None

    def _extract_parameters(
        self: "CircleBuilder",
        surface: Union[Standard, Toroidal],
        material: Material = None,
    ) -> None:
        """Extract parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal
        material : Material
            Custom mirror material. Default is None (ideal mirror).

        Returns
        -------
        None
        """
        if surface.semi_diameter < 1e-8:
            raise CannotCreatePrimitive(
                f"Cannot create Circle from {surface}: radius is too small: {surface.radius}"
            )

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type is not SurfaceType.FLAT:
            raise CannotCreatePrimitive(f"Cannot create Circle from {surface}: it is not flat")

        if shape_type is not ShapeType.ROUND:
            raise CannotCreatePrimitive(f"Cannot create Circle from {surface}: it is not round")

        if material and not isinstance(material, Material):
            raise TypeError(f"Cannot create a mirror from {surface}: material must be a Raysect Material.")

        self._radius = surface.semi_diameter
        self._material = material or find_material(surface.material)
        self._name = surface.name

    def build(
        self: "CircleBuilder",
        surface: Union[Standard, Toroidal],
        direction: Direction = 1,
        material: Material = None,
    ) -> Circle:
        """Create a raysect.primitive.Cylinder using parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal
        direction : {-1, 1}, default = 1
        material : Material
            Custom mirror material. Default is None (ideal mirror).

        Returns
        -------
        Circle
        """
        self._clear_parameters()
        self._extract_parameters(surface, material)

        return Circle(self._radius, material=self._material, name=self._name)


class RectangleBuilder(MirrorBuilder):
    """Builder class for flat rectangle type surfaces."""

    def __init__(self: "RectangleBuilder") -> None:
        """Initializes a new instance of RectangleBuilder and a set of parameters.

        Returns
        -------
        None
        """
        self._clear_parameters()

    def _clear_parameters(self: "RectangleBuilder") -> None:
        """Initialize a set of parameters.

        Returns
        -------
        None
        """
        self._width: float = None
        self._height: float = None
        self._material: Material = None
        self._name: str = None

    def _extract_parameters(
        self: "RectangleBuilder",
        surface: Union[Standard, Toroidal],
        material: Material = None,
    ) -> None:
        """Extract parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal
        material : Material
            Custom mirror material. Default is None (ideal mirror).

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
                f"Cannot create a Rectangle object from {surface}: aperture dimensions is not set"
            )

        if surface.aperture_decenter is not None:
            raise CannotCreatePrimitive(
                f"Cannot create a Rectangle object from {surface}: "
                "aperture decenter is not implemented"
            )

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type is not SurfaceType.FLAT:
            raise CannotCreatePrimitive(f"Cannot create Rectangle from {surface}: it is not flat")

        if shape_type is not ShapeType.RECTANGULAR:
            raise CannotCreatePrimitive(
                f"Cannot create Rectangle from {surface}: it is not rectangular"
            )

        self._width = surface.aperture[0] * 2
        self._height = surface.aperture[1] * 2
        self._material = material or find_material(surface.material)
        self._name = surface.name

    def build(
        self: "RectangleBuilder",
        surface: Union[Standard, Toroidal],
        direction: Direction = 1,
        material: Material = None,
    ) -> Rectangle:
        """Create an instance Rectangle using parameters from a surface description.

        Parameters
        ----------
        surface : Standard or Toroidal
        direction : {-1, 1}, default = 1
        material : Material
            Custom mirror material. Default is None (ideal mirror).

        Returns
        -------
        Circle
        """
        self._clear_parameters()
        self._extract_parameters(surface)

        return Rectangle(self._width, self._height, material=self._material, name=self._name)


class AbstractSurfacePrimitiveBuilder:
    """Abstract builder class for surface type primitives."""

    builders: Dict[str, MirrorBuilder] = {
        "circle": CircleBuilder,
        "rectangle": RectangleBuilder,
    }

    @classmethod
    def get_builder(cls: "AbstractSurfacePrimitiveBuilder", name: str) -> MirrorBuilder:
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
        cls: "AbstractSurfacePrimitiveBuilder",
        name: str,
        surface: Union[Standard, Toroidal],
        direction: Direction = 1,
        material: Material = None,
    ) -> Union[Circle, Rectangle]:
        """Build a primitive with a requested name.

        Parameters
        ----------
        name : str
        surface : Standard or Toroidal
        direction : {-1, 1}, default = 1
        material : Material
            Custom mirror material. Default is None (ideal mirror).

        Returns
        -------
        Circle or Rectangle
        """
        return cls.get_builder(name)().build(surface, direction, material)


def create_circle(surface: Union[Standard, Toroidal], direction: Direction = 1, material: Material = None) -> Circle:
    return CircleBuilder().build(surface, direction, material)


def create_rectangle(surface: Union[Standard, Toroidal], direction: Direction = 1, material: Material = None) -> Rectangle:
    return RectangleBuilder().build(surface, direction, material)
