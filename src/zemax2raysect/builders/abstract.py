"""Abstract builder classes for optical elements."""
from typing import Dict

from raysect.primitive import EncapsulatedPrimitive
from raysect.optical import Material

from ..surface import Surface
from .base import LensBuilder, MirrorBuilder, OpticsBuilder
from .common import Direction
from .cylindrical import CylindricalLensBuilder, CylindricalMirrorBuilder
from .spherical import SphericalLensBuilder, SphericalMirrorBuilder
from .surface import CircleBuilder, RectangleBuilder
from .toroidal import ToricLensBuilder, ToricMirrorBuilder


class AbstractOpticsBuilder:
    """Base class for abstract optics builder."""

    builders: Dict[str, OpticsBuilder]

    @classmethod
    def get_builder(cls: "AbstractOpticsBuilder", name: str) -> OpticsBuilder:
        raise NotImplementedError

    @classmethod
    def build(cls: "AbstractOpticsBuilder", name: str, *args, **kwargs) -> EncapsulatedPrimitive:
        raise NotImplementedError


class AbstractMirrorBuilder:

    builders: Dict[str, MirrorBuilder] = {
        "toroidal": ToricMirrorBuilder,
        "spherical": SphericalMirrorBuilder,
        "cylindrical": CylindricalMirrorBuilder,
        "rectangle": RectangleBuilder,
        "circle": CircleBuilder,
    }

    @classmethod
    def get_builder(cls: "AbstractMirrorBuilder", name: str) -> MirrorBuilder:

        if name not in cls.builders:
            msg = (
                f"Builder for '{name}' mirror is not implemented"
                f", try one of {tuple(name for name in cls.builders)}"
            )
            raise KeyError(msg)

        return cls.builders[name]

    @classmethod
    def build(
        cls: "AbstractMirrorBuilder",
        name: str,
        surface: Surface,
        direction: Direction,
        material: Material = None,
    ) -> EncapsulatedPrimitive:

        return cls.get_builder(name)().build(surface, direction, material)


class AbstractLensBuilder:

    builders: Dict[str, LensBuilder] = {
        "toroidal": ToricLensBuilder,
        "spherical": SphericalLensBuilder,
        "cylindrical": CylindricalLensBuilder,
    }

    @classmethod
    def get_builder(cls: "AbstractLensBuilder", name: str) -> LensBuilder:

        if name not in cls.builders:
            msg = (
                f"Builder for '{name}' lens is not implemented"
                f", try one of {tuple(name for name in cls.builders)}"
            )
            raise KeyError(msg)

        return cls.builders[name]

    @classmethod
    def build(
        cls: "AbstractLensBuilder",
        name: str,
        back_surface: Surface,
        front_surface: Surface,
        material: Material = None,
    ) -> EncapsulatedPrimitive:

        return cls.get_builder(name)().build(back_surface, front_surface, material)


def create_mirror(name: str, surface: Surface, direction: Direction, material: Material = None) -> EncapsulatedPrimitive:
    return AbstractMirrorBuilder.build(name, surface, direction, material)


def create_lens(name: str, back_surface: Surface, front_surface: Surface, material: Material = None) -> EncapsulatedPrimitive:
    return AbstractLensBuilder.build(name, back_surface, front_surface, material)
