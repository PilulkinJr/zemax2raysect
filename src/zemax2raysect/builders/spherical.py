"""Builder class for spherical mirrors and lenses."""
import logging
from typing import Type, Union

from raysect.core import Material, rotate_y
from raysect.primitive import Cylinder, EncapsulatedPrimitive
from raysect.primitive.lens import BiConcave, BiConvex, PlanoConcave, PlanoConvex

from ..materials import find_material
from ..primitive.lens.spherical import Meniscus
from ..primitive.mirror.spherical import SphericalMirror
from ..surface import Standard, Toroidal
from .base import LensBuilder, MirrorBuilder
from .common import (
    DEFAULT_THICKNESS,
    CannotCreatePrimitive,
    Direction,
    ShapeType,
    SurfaceType,
    determine_primitive_type,
    flip,
    sign,
)
from .flat import create_cylinder

LOGGER = logging.getLogger(__name__)


class SphericalMirrorBuilder(MirrorBuilder):
    """Builder class for SphericalMirror.

    Methods
    -------
    build(surface, direction) : SphericalMirror
        Build a SphericalMirror instance using Zemax surface description.
    """

    _CANNOT_CREATE_MSG = "Cannot create spherical mirror: "

    def _clear_parameters(self: "SphericalMirrorBuilder") -> None:
        """Initialize a set of parameters.

        Returns
        -------
        None
        """
        self._diameter: float = None
        self._center_thickness: float = None
        self._curvature: float = None
        self._material: Material = None
        self._name: str = None
        self._curvature_sign: int = None

    def _extract_parameters(
        self: "SphericalMirrorBuilder",
        surface: Union[Standard, Toroidal],
    ) -> None:
        """Extract required parameters from a surface description.

        Parameters
        ----------
        surface : Union[Standard, Toroidal]

        Returns
        -------
        None
        """
        if not isinstance(surface, (Standard, Toroidal)):
            raise CannotCreatePrimitive(
                self._CANNOT_CREATE_MSG
                + f"'surface' must be {Union[Standard, Toroidal]}, got {type(surface)}"
            )

        self._check_for_small_numbers(surface)

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type != SurfaceType.SPHERICAL:
            raise CannotCreatePrimitive(
                self._CANNOT_CREATE_MSG
                + f"'surface' {surface} does not define a spherical surface"
            )

        if shape_type not in (ShapeType.RECTANGULAR, ShapeType.ROUND):
            raise CannotCreatePrimitive(
                self._CANNOT_CREATE_MSG
                + f"aperture type of 'surface' {surface} is not implemented"
            )

        if shape_type == ShapeType.RECTANGULAR:
            LOGGER.warning(
                "Despite of having a rectangular aperture, "
                "surface will be made into a round mirror"
            )

        self._diameter = 2 * surface.semi_diameter
        self._center_thickness = surface.thickness or DEFAULT_THICKNESS
        self._curvature = abs(surface.radius)
        self._material = find_material(surface.material)
        self._name = surface.name
        self._curvature_sign = sign(surface.radius)

    def build(
        self: "SphericalMirrorBuilder",
        surface: Union[Standard, Toroidal],
        direction: Direction = 1,
    ) -> SphericalMirror:
        """Build a SphericalMirror using Zemax surface.

        Parameters
        ----------
        surface : Union[Standard, Toroidal]
            Toroidal type surface can define a spherical surface if curvatures are equal.
        direction : -1 or 1, default = 1
            Handles a Zemax ray propagation direction.

        Returns
        -------
        SphericalMirror
        """
        self._clear_parameters()
        self._extract_parameters(surface)

        # mirror = SphericalMirror(
        #     self._diameter,
        #     self._center_thickness,
        #     self._curvature,
        #     material=self._material,
        #     name=self._name,
        # )

        # mirror.transform = transform_according_to_direction(
        #     mirror, direction, self._curvature_sign
        # )

        mirror = SphericalMirror(
            self._diameter,
            self._curvature,
            material=self._material,
            name=self._name,
        )

        if direction == 1 and self._curvature_sign == -1:
            LOGGER.debug("Rotating mirror %s around y axis", mirror.name)
            mirror.transform = rotate_y(180)
        # else:
        #     mirror.transform = AffineMatrix3D()

        return mirror


class SphericalLensBuilder(LensBuilder):
    """Builder class for spherical lenses.

    Methods
    -------
    build(back_surface, front_surface) : raysect.primitive.EncapsulatedPrimitive
        Build a new lens using parameters stored in two surfaces.
        Type of lens (biconvex, biconcave, etc.) automatically resolved using those parameters.
    """

    _CANNOT_CREATE_MSG = "Cannot create spherical lens: "

    def __init__(self: "SphericalLensBuilder") -> None:
        """Create a new SphericalLensBuilder instance with lens parameters cleared.

        Returns
        -------
        None
        """
        self._clear_parameters()

    def _clear_parameters(self: "SphericalLensBuilder") -> None:
        """Define lens parameters as private or clear them.

        Returns
        -------
        None
        """
        self._diameter: float = None
        self._center_thickness: float = None
        self._back_curvature: float = None
        self._front_curvature: float = None
        self._material: Material = None
        self._name: str = None

    def _extract_parameters(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> None:
        """Extract lens parameters from two surfaces.

        Parameters
        ----------
        back_surface, front_surface : Union[Standard, Toroidal]

        Returns
        -------
        None
        """
        self._check_for_material(back_surface)
        self._check_for_small_numbers(back_surface)
        self._check_for_small_numbers(front_surface)

        back_surface_type, back_shape_type = determine_primitive_type(back_surface)
        front_surface_type, front_shape_type = determine_primitive_type(front_surface)

        if back_surface_type not in (SurfaceType.FLAT, SurfaceType.SPHERICAL):
            raise CannotCreatePrimitive(
                self._CANNOT_CREATE_MSG
                + f"'back_surface' {back_surface} does not define a spherical or flat surface"
            )

        if front_surface_type not in (SurfaceType.FLAT, SurfaceType.SPHERICAL):
            raise CannotCreatePrimitive(
                self._CANNOT_CREATE_MSG
                + f"'front_surface' {front_surface} does not define a spherical or flat surface"
            )

        if back_shape_type is not ShapeType.ROUND:
            LOGGER.warning("'back_surface' has non-round aperture which is not supported")

        if front_shape_type is not ShapeType.ROUND:
            LOGGER.warning("'front_surface' has non-round aperture which is not supported")

        self._diameter = back_surface.semi_diameter * 2 or front_surface.semi_diameter * 2
        self._center_thickness = back_surface.thickness
        self._back_curvature = abs(back_surface.radius)
        self._front_curvature = abs(front_surface.radius)
        self._material = find_material(back_surface.material)
        self._name = back_surface.name or front_surface.name

    def _build_bicurve_lens(
        self: "SphericalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> EncapsulatedPrimitive:
        """Build bi-curved lens of class 'lens_class'.

        Parameters
        ----------
        lens_class : subclass of raysect.primitive.EncapsulatedPrimitive
        back_surface : Union[Standard, Toroidal]
        front_surface : Union[Standard, Toroidal]

        Returns
        -------
        raysect.primitive.EncapsulatedPrimitive
        """
        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface)

        return lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            back_curvature=self._back_curvature,
            front_curvature=self._front_curvature,
            material=self._material,
            name=self._name,
        )

    def _flip_bicurve_lens(
        self: "SphericalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> EncapsulatedPrimitive:

        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface)

        lens = lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            back_curvature=self._front_curvature,
            front_curvature=self._back_curvature,
            material=self._material,
            name=self._name,
        )
        lens.transform = flip(lens.center_thickness)

        return lens

    def _build_degenerate_lens(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> Cylinder:
        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface)

        return Cylinder(
            self._diameter * 0.5,
            self._center_thickness,
            material=self._material,
            name=self._name,
        )

    def _build_positive_meniscus(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> Meniscus:
        return self._build_bicurve_lens(Meniscus, back_surface, front_surface)

    def _build_negative_meniscus(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> Meniscus:
        return self._flip_bicurve_lens(Meniscus, back_surface, front_surface)

    def _build_biconvex(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> BiConvex:
        return self._build_bicurve_lens(BiConvex, back_surface, front_surface)

    def _build_biconcave(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> BiConcave:
        return self._build_bicurve_lens(BiConcave, back_surface, front_surface)

    def _build_singlecurve_lens(
        self: "SphericalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> EncapsulatedPrimitive:

        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface)

        return lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            curvature=self._front_curvature,
            material=self._material,
            name=self._name,
        )

    def _flip_singlecurve_lens(
        self: "SphericalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> EncapsulatedPrimitive:

        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface)

        lens = lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            curvature=self._back_curvature,
            material=self._material,
            name=self._name,
        )

        lens.transform = flip(lens.center_thickness)

        return lens

    def _build_planoconcave(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> PlanoConcave:
        return self._build_singlecurve_lens(PlanoConcave, back_surface, front_surface)

    def _build_concaveplano(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> PlanoConcave:
        return self._flip_singlecurve_lens(PlanoConcave, back_surface, front_surface)

    def _build_planoconvex(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> PlanoConvex:
        return self._build_singlecurve_lens(PlanoConvex, back_surface, front_surface)

    def _build_convexplano(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> PlanoConvex:
        return self._flip_singlecurve_lens(PlanoConvex, back_surface, front_surface)

    def build(
        self: "SphericalLensBuilder",
        back_surface: Union[Standard, Toroidal],
        front_surface: Union[Standard, Toroidal],
    ) -> Union[Meniscus, BiConvex, BiConcave, PlanoConvex, PlanoConcave]:
        """Build a spherical lens using Zemax surface.

        Parameters
        ----------
        back_surface, front_surface : Standard or Toroidal
            Surfaces defining a spherical lens.

        Returns
        -------
        {Meniscus, BiConvex, BiConcave, PlanoConvex, PlanoConcave}
        """
        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface)

        back_sgn = sign(back_surface.radius)
        front_sgn = sign(front_surface.radius)

        if back_sgn == 0 and front_sgn == 0:
            return create_cylinder(back_surface)

        if back_sgn < 0 and front_sgn < 0:
            return self._build_positive_meniscus(back_surface, front_surface)

        if back_sgn > 0 and front_sgn > 0:
            return self._build_negative_meniscus(back_surface, front_surface)

        if back_sgn > 0 and front_sgn < 0:
            return self._build_biconvex(back_surface, front_surface)

        if back_sgn < 0 and front_sgn > 0:
            return self._build_biconcave(back_surface, front_surface)

        if back_sgn == 0:

            if front_sgn < 0:
                return self._build_planoconvex(back_surface, front_surface)

            return self._build_planoconcave(back_surface, front_surface)

        if front_sgn == 0:

            if back_sgn > 0:
                return self._build_convexplano(back_surface, front_surface)

            return self._build_concaveplano(back_surface, front_surface)

        raise CannotCreatePrimitive(
            f"Cannot create spherical lens from {back_surface} and {front_surface}"
        )


def create_spherical_mirror(
    surface: Union[Standard, Toroidal],
    direction: Direction = 1,
) -> SphericalMirror:
    return SphericalMirrorBuilder().build(surface, direction)


def create_spherical_lens(
    back_surface: Union[Standard, Toroidal],
    front_surface: Union[Standard, Toroidal],
) -> Union[Meniscus, BiConvex, BiConcave, PlanoConvex, PlanoConcave]:
    """Build a spherical lens primitive using two surfaces.

    Parameters
    ----------
    back_surface, front_surface : Standard or Toroidal

    Returns
    -------
    {Meniscus, BiConvex, BiConcave, PlanoConvex, PlanoConcave}
    """
    return SphericalLensBuilder().build(back_surface, front_surface)
