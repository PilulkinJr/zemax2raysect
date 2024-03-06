"""Base classes for optical builders."""
from raysect.primitive import EncapsulatedPrimitive
from raysect.optical import Material

from ..surface import Surface
from .common import CannotCreatePrimitive, Direction

SMALL_NUMBER = 1.0e-8
NOT_IMPLEMENTED_MESSAGE = "This method must be implemented by a subclass"


class OpticsBuilder:
    """Base builder class for any optical element."""

    def __init__(self: "OpticsBuilder") -> None:
        self._clear_parameters()

    def _clear_parameters(self: "OpticsBuilder") -> None:
        """Initialize parameters.

        This method should initialize a set of parameters
        which will be used to build an optical element.

        Returns
        -------
        None
        """
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _extract_parameters(self: "OpticsBuilder", *args: Surface, material: Material = None) -> None:
        """Extract parameters required to build an optical element.

        Parameters
        ----------
        args : Surface
        material : Material
            Default is None. User-defined Raysect optical material for a mirror or a lens.

        Returns
        -------
        None
        """
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def build(self: "OpticsBuilder", *args: Surface, material: Material = None) -> EncapsulatedPrimitive:
        """Build an optical element.

        Parameters
        ----------
        args : Surface
            A sequence of surfaces which define an optical element.
            For example, one -- for a mirror, two -- for a lens.
        material : Material
            Default is None. User-defined Raysect optical material for a mirror or a lens.

        Returns
        -------
        EncapsulatedPrimitive
        """
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    @staticmethod
    def _check_for_small_numbers(surface: Surface) -> None:
        """Check if surface parameters are too small.

        Used to catch a point sources, for example.

        Parameters
        ----------
        surface : Surface

        Returns
        -------
        None
        """
        if surface.semi_diameter < SMALL_NUMBER:
            msg = f"Semi-diameter of the surface {surface} is too small: {surface.semi_diameter}"
            raise CannotCreatePrimitive(msg)

        if 0 < surface.thickness < SMALL_NUMBER:
            msg = f"Thickness of the surface {surface} is too small: {surface.thickness}"
            raise CannotCreatePrimitive(msg)


class MirrorBuilder(OpticsBuilder):
    """Builder class for mirrors.

    Methods
    -------
    build(surface) : EncapsulatedPrimitive
        Build a mirror using a surface parameters.
    """

    def _extract_parameters(self: "LensBuilder", surface: Surface, material: Material = None) -> None:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def build(
        self: "MirrorBuilder", surface: Surface, direction: Direction, material: Material = None
    ) -> EncapsulatedPrimitive:
        """Build a mirror using a surface parameters.

        Parameters
        ----------
        surface : Surface
        direction : {-1, 1}
            Ray propagation direction.
        material : Material
            Default is None. User-defined Raysect optical material of the mirror.

        Returns
        -------
        EncapsulatedPrimitive
        """
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)


class LensBuilder(OpticsBuilder):
    def _extract_parameters(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface, material: Material = None
    ) -> None:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def build(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface, material: Material = None
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_positive_meniscus(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_negative_meniscus(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_biconvex(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_biconcave(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_planoconcave(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_concaveplano(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_planoconvex(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    def _build_convexplano(
        self: "LensBuilder", back_surface: Surface, front_surface: Surface
    ) -> EncapsulatedPrimitive:
        raise NotImplementedError(NOT_IMPLEMENTED_MESSAGE)

    @staticmethod
    def _check_for_material(back_surface: Surface) -> None:
        """Check if back surface of the lens is assigned a material.

        For two sequential surfaces to form a lens,
        the first one (back) has to be assigned a material.

        Parameters
        ----------
        back_surface : Surface

        Returns
        -------
        None
        """
        # if not issubclass(type(back_surface), Surface):
        #     raise TypeError(
        #         f"'back_surface' has to be a subclass of {Surface}, got {type(back_surface)}"
        #     )

        # if not hasattr(back_surface, "material"):
        #     raise AttributeError("'back_surface' must have a 'material' attribute")

        if not isinstance(back_surface.material, str):
            raise TypeError(
                f"back_surface.material must be {str}, got {type(back_surface.material)}"
            )

        if not back_surface.material:
            raise CannotCreatePrimitive("back_surface must be assigned a material")
