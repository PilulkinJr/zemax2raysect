"""Builder class for cylindrical mirrors and lenses."""
import logging
from typing import Type, Union, Tuple

from raysect.core import AffineMatrix3D, Material, rotate_z
from raysect.primitive import EncapsulatedPrimitive

from ..materials import find_material
from ..primitive.lens.cylindrical import (
    CylindricalBiConcave,
    CylindricalBiConvex,
    CylindricalMeniscus,
    CylindricalPlanoConcave,
    CylindricalPlanoConvex,
)
from ..primitive.mirror.cylindrical import RoundCylindricalMirror, RectangularCylindricalMirror
from ..surface import Toroidal
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
    transform_according_to_direction,
)
from .flat import create_cylinder

LOGGER = logging.getLogger(__name__)


class CylindricalMirrorBuilder(MirrorBuilder):
    """Builder class for cylindrical mirror primitive."""

    def _clear_parameters(self: "CylindricalMirrorBuilder") -> None:
        self._diameter: float = None
        self._width: float = None
        self._height: float = None
        self._curvature: float = None
        self._aperture: float = 0
        self._horizontal_decenter: float = 0
        self._vertical_decenter: float = 0
        self._shape_type: str = ShapeType.UNDETERMINED
        self._material: Material = None
        self._name: str = None
        self._curvature_sign: int = None
        self._rotation: AffineMatrix3D = AffineMatrix3D()

    def _extract_parameters(self: "CylindricalMirrorBuilder", surface: Toroidal, material: Material = None) -> None:
        if not isinstance(surface, Toroidal):
            raise CannotCreatePrimitive(
                f"Cannot create cylindrical mirror from {surface}"
                f": 'surface' has to be {Toroidal}, got {type(surface)}"
            )

        self._check_for_small_numbers(surface)

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type != SurfaceType.CYLINDRICAL:
            raise CannotCreatePrimitive(
                f"Cannot create cylindrical mirror from {surface}: it is not cylindrical"
            )

        if shape_type not in (ShapeType.RECTANGULAR, ShapeType.ROUND):
            raise CannotCreatePrimitive(
                f"Cannot create cylindrical mirror from {surface}"
                ": it is not a circle, nor a rectangle"
            )

        if material and not isinstance(material, Material):
            raise TypeError(f"Cannot create a mirror from {surface}: material must be a Raysect Material.")

        if surface.radius != 0:

            if surface.radius_horizontal != 0:
                raise CannotCreatePrimitive(
                    f"Cannot create cylindrical mirror from {surface}"
                    ": the surface is not cylindrical but toroidal."
                )

            self._curvature = abs(surface.radius)
            self._curvature_sign = sign(surface.radius)
            self._rotation = AffineMatrix3D()

            if shape_type is ShapeType.RECTANGULAR:
                self._width = 2 * surface.aperture[0]
                self._height = 2 * surface.aperture[1]
            if surface.aperture_decenter:
                self._horizontal_decenter = surface.aperture_decenter[0]
                self._vertical_decenter = surface.aperture_decenter[1]

        elif surface.radius_horizontal != 0:

            self._curvature = abs(surface.radius_horizontal)
            self._curvature_sign = sign(surface.radius_horizontal)
            self._rotation = rotate_z(90)

            if shape_type is ShapeType.RECTANGULAR:
                self._width = 2 * surface.aperture[1]
                self._height = 2 * surface.aperture[0]
            if surface.aperture_decenter:
                self._horizontal_decenter = -surface.aperture_decenter[1]
                self._vertical_decenter = surface.aperture_decenter[0]

        else:
            raise CannotCreatePrimitive(
                f"Cannot create cylindrical mirror from {surface}"
                ": the surface is flat."
            )

        self._shape_type = shape_type

        if shape_type is ShapeType.ROUND:
            if surface.aperture:
                self._diameter = 2 * surface.aperture[1]
                self._aperture = 2 * surface.aperture[0]
            else:
                self._diameter = 2 * surface.semi_diameter

        if self._curvature_sign == -1:
            self._horizontal_decenter = -self._horizontal_decenter

        self._material = material or find_material(surface.material)
        self._name = surface.name

    def build(
        self: "CylindricalMirrorBuilder",
        surface: Toroidal,
        direction: Direction = 1,
        material: Material = None,
    ) -> Union[
        RoundCylindricalMirror,
        RectangularCylindricalMirror
    ]:
        """Build a cylindrical mirror primitive.

        Parameters
        ----------
        surface : Toroidal
        direction : {-1, 1}, default = 1
            Ray propagation direction.
        material : Material
            Custom mirror material. Default is None (ideal mirror).

        Returns
        -------
        RoundCylindricalMirror or RectangularCylindricalMirror
        """
        self._clear_parameters()
        self._extract_parameters(surface, material)

        if self._shape_type == ShapeType.ROUND:
            mirror = RoundCylindricalMirror(
                self._diameter,
                self._curvature,
                aperture=self._aperture,
                horizontal_decenter=self._horizontal_decenter,
                vertical_decenter=self._vertical_decenter,
                material=self._material,
                name=self._name,
            )
        else:
            mirror = RectangularCylindricalMirror(
                self._width,
                self._height,
                self._curvature,
                aperture=self._aperture,
                horizontal_decenter=self._horizontal_decenter,
                vertical_decenter=self._vertical_decenter,
                material=self._material,
                name=self._name,
            )
        mirror.transform = (
            transform_according_to_direction(mirror, direction, self._curvature_sign)
            * self._rotation
        )

        return mirror


class CylindricalLensBuilder(LensBuilder):
    """Builder class for cylindrical lens primitives."""

    def _clear_parameters(self: "CylindricalLensBuilder") -> None:
        self._diameter: float = None
        self._center_thickness: float = None
        self._back_curvature: float = None
        self._front_curvature: float = None
        self._material: Material = None
        self._name: str = None
        self._rotation: AffineMatrix3D = AffineMatrix3D()
        self._back_sgn: int = None
        self._front_sgn: int = None

    def _extract_parameters(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
        material: Material = None,
    ) -> None:
        """Extract lens parameters from two surfaces.

        Parameters
        ----------
        back_surface, front_surface : Toroidal
            Two sequential surfaces defining a cylindrical lens.
        material: Material
            Custom lens material. Default is None
            (will search back_surface.material in the Raysect library).

        Returns
        -------
        None
        """
        if material and not isinstance(material, Material):
            raise TypeError(f"Cannot create a lens from {back_surface.name, front_surface.name}:"
                            " material must be a Raysect Material.")

        if not material:
            self._check_for_material(back_surface)
        self._check_for_small_numbers(back_surface)
        self._check_for_small_numbers(front_surface)

        back_surface_type, back_shape_type = determine_primitive_type(back_surface)
        front_surface_type, front_shape_type = determine_primitive_type(front_surface)

        if back_surface_type not in (SurfaceType.FLAT, SurfaceType.CYLINDRICAL):
            raise CannotCreatePrimitive(
                f"Cannot create cylindrical lens from {back_surface.name}"
                f" - surface type is {back_surface_type}"
            )

        if front_surface_type not in (SurfaceType.FLAT, SurfaceType.CYLINDRICAL):
            raise CannotCreatePrimitive(
                f"Cannot create cylindrical lens from {front_surface.name}"
                f" - surface type is {front_surface_type}"
            )

        if back_surface_type is SurfaceType.FLAT and front_surface_type is SurfaceType.FLAT:
            raise CannotCreatePrimitive("Cannot create cylindrical lens: both surfaces are flat")

        if back_shape_type is not ShapeType.ROUND or front_shape_type is not ShapeType.ROUND:
            raise CannotCreatePrimitive(
                f"{back_surface.name} or {front_surface.name} is not round"
            )

        if back_surface.radius_horizontal == 0:

            if front_surface.radius_horizontal != 0:
                raise NotImplementedError("Cylindrical lens faces have different orientations")

            self._back_curvature = abs(back_surface.radius)
            self._back_sgn = sign(back_surface.radius)
            self._front_curvature = abs(front_surface.radius)
            self._front_sgn = sign(front_surface.radius)
            self._rotation = AffineMatrix3D()

        elif back_surface.radius == 0:

            if front_surface.radius != 0:
                raise NotImplementedError("Cylindrical lens faces have different orientations")

            self._back_curvature = abs(back_surface.radius_horizontal)
            self._back_sgn = sign(back_surface.radius_horizontal)
            self._front_curvature = abs(front_surface.radius_horizontal)
            self._front_sgn = sign(front_surface.radius_horizontal)
            self._rotation = rotate_z(90)

        elif back_surface.radius != back_surface.radius_horizontal:
            raise CannotCreatePrimitive(f"{back_surface} defines a totoidal surface")

        # if abs(back_surface.radius) >= 0:

        #     if back_surface.radius_horizontal != 0 and back_surface.radius != 0:
        #         raise ValueError(f"{back_surface} defines a totoidal surface")

        #     if front_surface.radius_horizontal != 0 and back_surface.radius != 0:
        #         raise NotImplementedError(
        #             "Cylindrical lens with differently oriented faces is not implemented"
        #         )

        #     self._back_curvature = abs(back_surface.radius)
        #     self._back_sgn = sign(back_surface.radius)
        #     self._front_curvature = abs(front_surface.radius)
        #     self._front_sgn = sign(front_surface.radius)
        #     self._rotation = AffineMatrix3D()

        # if abs(back_surface.radius_horizontal) >= 0:

        #     if front_surface.radius != 0 and back_surface.radius_horizontal != 0:
        #         raise NotImplementedError(
        #             "Cylindrical lens with differently oriented faces is not implemented"
        #         )

        #     self._back_curvature = abs(back_surface.radius_horizontal)
        #     self._back_sgn = sign(back_surface.radius_horizontal)
        #     self._front_curvature = abs(front_surface.radius_horizontal)
        #     self._front_sgn = sign(front_surface.radius_horizontal)
        #     self._rotation = rotate_z(90)

        self._diameter = back_surface.semi_diameter * 2 or front_surface.semi_diameter * 2
        self._center_thickness = back_surface.thickness or DEFAULT_THICKNESS
        self._material = material or find_material(back_surface.material)
        self._name = back_surface.name or front_surface.name

    def build(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
        material: Material = None,
    ) -> Union[
        CylindricalBiConvex,
        CylindricalBiConcave,
        CylindricalMeniscus,
        CylindricalPlanoConvex,
        CylindricalPlanoConcave,
    ]:
        """Build a cylindrical lens primitive using two surfaces.

        Parameters
        ----------
        back_surface, front_surface : Toroidal
        material : Material
            Custom lens material. Default is None
            (will search back_surface.material in the Raysect library).

        Returns
        -------
        Union[BiConvex, BiConcave, Meniscus, PlanoConvex, PlanoConcave]
        """
        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface, material)

        LOGGER.debug(
            "Building cylindrical lens: back_sgn = %g, back_sgn = %g",
            self._back_sgn,
            self._front_sgn,
        )

        if self._back_sgn == 0 and self._front_sgn == 0:
            return create_cylinder(back_surface)

        if self._back_sgn < 0 and self._front_sgn < 0:
            LOGGER.debug("%s is a positive meniscus", back_surface.name)
            return self._build_positive_meniscus(back_surface, front_surface)

        if self._back_sgn > 0 and self._front_sgn > 0:
            LOGGER.debug("%s is a negative meniscus", back_surface.name)
            return self._build_negative_meniscus(back_surface, front_surface)

        if self._back_sgn > 0 and self._front_sgn < 0:
            LOGGER.debug("%s is a biconvex lens", back_surface.name)
            return self._build_biconvex(back_surface, front_surface)

        if self._back_sgn < 0 and self._front_sgn > 0:
            LOGGER.debug("%s is a biconcave lens", back_surface.name)
            return self._build_biconcave(back_surface, front_surface)

        if self._back_sgn == 0:

            if self._front_sgn < 0:
                LOGGER.debug("%s is a plano-convex lens", back_surface.name)
                return self._build_planoconvex(back_surface, front_surface)

            LOGGER.debug("%s is a plano-concave lens", back_surface.name)
            return self._build_planoconcave(back_surface, front_surface)

        if self._front_sgn == 0:

            if self._back_sgn > 0:
                LOGGER.debug("%s is a convex-plano lens", back_surface.name)
                return self._build_convexplano(back_surface, front_surface)

            LOGGER.debug("%s is a concave-plano lens", back_surface.name)
            return self._build_concaveplano(back_surface, front_surface)

        raise CannotCreatePrimitive(
            f"Cannot create lens from {back_surface.name} and {front_surface.name}"
        )

    def _build_plano_lens(
        self: "CylindricalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> Union[CylindricalPlanoConvex, CylindricalPlanoConcave]:

        lens = lens_class(
            self._diameter,
            self._center_thickness,
            self._front_curvature,
            material=self._material,
            name=self._name,
        )
        lens.transform = self._rotation

        return lens

    def _flip_plano_lens(
        self: "CylindricalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> Union[CylindricalPlanoConvex, CylindricalPlanoConcave]:

        lens = lens_class(
            self._diameter,
            self._center_thickness,
            self._back_curvature,
            material=self._material,
            name=self._name,
        )
        lens.transform = flip(lens.center_thickness) * self._rotation

        return lens

    def _build_planoconcave(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalPlanoConcave:
        return self._build_plano_lens(CylindricalPlanoConcave, back_surface, front_surface)

    def _build_concaveplano(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalPlanoConcave:
        return self._flip_plano_lens(CylindricalPlanoConcave, back_surface, front_surface)

    def _build_planoconvex(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalPlanoConvex:
        return self._build_plano_lens(CylindricalPlanoConvex, back_surface, front_surface)

    def _build_convexplano(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalPlanoConvex:
        return self._flip_plano_lens(CylindricalPlanoConvex, back_surface, front_surface)

    def _build_bi_lens(
        self: "CylindricalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> Union[CylindricalBiConvex, CylindricalBiConcave, CylindricalMeniscus]:

        lens = lens_class(
            self._diameter,
            self._center_thickness,
            self._front_curvature,
            self._back_curvature,
            material=self._material,
            name=self._name,
        )
        lens.transform = self._rotation

        return lens

    def _flip_bi_lens(
        self: "CylindricalLensBuilder",
        lens_class: Type[EncapsulatedPrimitive],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalMeniscus:

        lens = lens_class(
            self._diameter,
            self._center_thickness,
            self._back_curvature,
            self._front_curvature,
            material=self._material,
            name=self._name,
        )
        lens.transform = flip(lens.center_thickness) * self._rotation

        return lens

    def _build_biconvex(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalBiConvex:
        return self._build_bi_lens(CylindricalBiConvex, back_surface, front_surface)

    def _build_biconcave(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalBiConcave:
        return self._build_bi_lens(CylindricalBiConcave, back_surface, front_surface)

    def _build_positive_meniscus(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalMeniscus:
        return self._build_bi_lens(CylindricalMeniscus, back_surface, front_surface)

    def _build_negative_meniscus(
        self: "CylindricalLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> CylindricalMeniscus:
        return self._flip_bi_lens(CylindricalMeniscus, back_surface, front_surface)
