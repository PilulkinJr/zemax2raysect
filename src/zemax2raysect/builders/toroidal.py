"""Builder class for toroidal mirrors and lenses."""
import logging
from typing import Type, Union

from raysect.core import Material, rotate_y

from ..materials import find_material
from ..primitive.lens.toric import (
    ToricBiConcave,
    ToricBiConvex,
    ToricMeniscus,
    ToricPlanoConcave,
    ToricPlanoConvex,
)
from ..primitive.mirror.toric import ToricMirror
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
)
from .flat import create_cylinder

LOGGER = logging.getLogger(__name__)


class ToricMirrorBuilder(MirrorBuilder):
    """Builder class for ToricMirror.

    Methods
    -------
    build(surface, direction, material=None) : ToricMirror
        Build a ToricMirror instance using Zemax surface description.
    """

    def __init__(self: "ToricMirrorBuilder") -> None:
        """Initialize a new builder and a set of parameters.

        Returns
        -------
        None
        """
        self._clear_parameters()

    def _clear_parameters(self: "ToricMirrorBuilder") -> None:
        """Initialize a set of parameters.

        Returns
        -------
        None
        """
        self._diameter: float = None
        self._center_thickness: float = None
        self._vertical_curvature: float = None
        self._horizontal_curvature: float = None
        self._material: Material = None
        self._name: str = None
        self._curvature_sign: int = None

    def _extract_parameters(self: "ToricMirrorBuilder", surface: Toroidal, material: Material = None) -> None:
        """Extract required parameters from a surface description.

        Parameters
        ----------
        surface : Toroidal
        material : Material
            Custom mirror material. Default is None (ideal mirror).

        Returns
        -------
        None
        """
        if not isinstance(surface, Toroidal):
            raise CannotCreatePrimitive(
                f"Cannot create toric mirror from {surface}: "
                f"it has to be {Toroidal}, got {type(surface)}"
            )

        self._check_for_small_numbers(surface)

        surface_type, shape_type = determine_primitive_type(surface)

        if surface_type != SurfaceType.TOROIDAL:
            raise CannotCreatePrimitive(
                f"Cannot create toric mirror from {surface}: it is not toric"
            )

        if sign(surface.radius) != sign(surface.radius_horizontal):
            raise NotImplementedError(
                "Toric surfaces with curvature radii of different signs are not implemented"
            )

        if shape_type not in (ShapeType.RECTANGULAR, ShapeType.ROUND):
            raise CannotCreatePrimitive(f"Surface {surface} not a circle, nor a rectangle")

        if material and not isinstance(material, Material):
            raise TypeError(f"Cannot create a mirror from {surface}: material must be a Raysect Material.")

        if shape_type == ShapeType.RECTANGULAR:
            LOGGER.warning(
                "Despite of having a rectangular aperture, "
                "surface will be made into a round mirror"
            )

        self._diameter = 2 * surface.semi_diameter
        self._center_thickness = abs(surface.thickness) or DEFAULT_THICKNESS
        self._vertical_curvature = abs(surface.radius)
        self._horizontal_curvature = abs(surface.radius_horizontal)
        self._material = material or find_material(surface.material)
        self._name = surface.name
        self._curvature_sign = sign(surface.radius)

    def build(
        self: "ToricMirrorBuilder",
        surface: Toroidal,
        direction: Direction = 1,
        material: Material = None,
    ) -> ToricMirror:
        """Build a ToricMirror using Zemax surface.

        Parameters
        ----------
        surface : Toroidal
        direction : -1 or 1, default = 1
            Handles a Zemax ray propagation direction.
        material : Material
            Custom mirror material. Default is None (ideal mirror).        

        Returns
        -------
        ToricMirror
        """
        self._clear_parameters()
        self._extract_parameters(surface, material)

        # mirror = ToricMirror(
        #     self._diameter,
        #     self._center_thickness,
        #     self._vertical_curvature,
        #     self._horizontal_curvature,
        #     material=self._material,
        #     name=self._name,
        # )
        # mirror.transform = transform_according_to_direction(
        #     mirror, direction, self._curvature_sign
        # )

        mirror = ToricMirror(
            self._diameter,
            self._vertical_curvature,
            self._horizontal_curvature,
            material=self._material,
            name=self._name,
        )

        if direction == 1 and self._curvature_sign == -1:
            LOGGER.debug("Rotating mirror %s around y axis", mirror.name)
            mirror.transform = rotate_y(180)

        return mirror


class ToricLensBuilder(LensBuilder):
    """Builder class for toric lenses."""

    def _clear_parameters(self: "ToricLensBuilder") -> None:
        self._diameter: float = None
        self._center_thickness: float = None
        self._back_curvature_vertical: float = None
        self._back_curvature_horizontal: float = None
        self._front_curvature_vertical: float = None
        self._front_curvature_horizontal: float = None
        self._material: Material = None
        self._name: str = None

    def _extract_parameters(
        self: "ToricLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
        material: Material = None,
    ) -> None:

        if material and not isinstance(material, Material):
            raise TypeError(f"Cannot create a lens from {back_surface.name, front_surface.name}:"
                            " material must be a Raysect Material.")

        if not material:
            self._check_for_material(back_surface)
        self._check_for_small_numbers(back_surface)
        self._check_for_small_numbers(front_surface)

        for surface in (back_surface, front_surface):
            if not isinstance(surface, Toroidal):
                raise CannotCreatePrimitive(
                    f"Both surfaces must be {Toroidal}, got {type(surface)}"
                )

        back_surface_type, back_shape_type = determine_primitive_type(back_surface)

        if back_surface_type not in (SurfaceType.FLAT, SurfaceType.TOROIDAL):
            msg = (
                "Cannot create toric lens"
                f": 'back_surface' {back_surface} does not define a toric or flat surface"
            )
            raise CannotCreatePrimitive(msg)

        if back_shape_type is not ShapeType.ROUND:
            LOGGER.warning("'back_surface' has non-round aperture which is not supported")

        front_surface_type, front_shape_type = determine_primitive_type(front_surface)

        if front_surface_type not in (SurfaceType.FLAT, SurfaceType.TOROIDAL):
            msg = (
                "Cannot create toric lens"
                f": 'front_surface' {front_surface} does not define a toric or flat surface"
            )
            raise CannotCreatePrimitive(msg)

        if front_shape_type is not ShapeType.ROUND:
            LOGGER.warning("'front_surface' has non-round aperture which is not supported")

        if sign(back_surface.radius) == (-1) * sign(back_surface.radius_horizontal):
            raise ValueError

        if sign(front_surface.radius) == (-1) * sign(front_surface.radius_horizontal):
            raise ValueError

        self._diameter = back_surface.semi_diameter * 2
        self._center_thickness = back_surface.thickness
        self._back_curvature_vertical = abs(back_surface.radius)
        self._back_curvature_horizontal = abs(back_surface.radius_horizontal)
        self._front_curvature_vertical = abs(front_surface.radius)
        self._front_curvature_horizontal = abs(front_surface.radius_horizontal)
        self._material = material or find_material(back_surface.material)
        self._name = back_surface.name or front_surface.name

    def build(
        self: "ToricLensBuilder",
        back_surface: Toroidal,
        front_surface: Toroidal,
        direction: Direction = 1,
        material: Material = None,
    ) -> Union[ToricBiConvex, ToricBiConcave, ToricMeniscus, ToricPlanoConvex, ToricPlanoConcave]:
        """Build a toric lens using two Zemax surfaces.

        Parameters
        ----------
        back_surface, front_surface : Toroidal
            Surfaces defining a lens.
        material : Material
            Custom lens material. Default is None (will search back_surface.material in the Raysect library).
        direction : -1 or 1, default = 1
            Handles a Zemax ray propagation direction.
        Returns
        -------
        EncapsulatedPrimitive
        """
        self._clear_parameters()
        self._extract_parameters(back_surface, front_surface, material)

        back_sgn = sign(back_surface.radius) * sign(direction)
        front_sgn = sign(front_surface.radius) * sign(direction)

        if back_sgn == 0 and front_sgn == 0:
            return create_cylinder(back_surface)

        if back_sgn > 0 and front_sgn < 0:
            return self._build_bi_lens(ToricBiConvex, back_surface, front_surface)

        if back_sgn < 0 and front_sgn > 0:
            return self._build_bi_lens(ToricBiConcave, back_surface, front_surface)

        if back_sgn < 0 and front_sgn < 0:
            return self._build_bi_lens(ToricMeniscus, back_surface, front_surface)

        if back_sgn > 0 and front_sgn > 0:
            return self._flip_bi_lens(ToricMeniscus, back_surface, front_surface)

        if back_sgn == 0:

            if front_sgn < 0:
                return self._build_plano_lens(ToricPlanoConvex, back_surface, front_surface)

            return self._build_plano_lens(ToricPlanoConcave, back_surface, front_surface)

        if front_sgn == 0:

            if back_sgn > 0:
                return self._flip_plano_lens(ToricPlanoConvex, back_surface, front_surface)

            return self._flip_plano_lens(ToricPlanoConcave, back_surface, front_surface)

        raise CannotCreatePrimitive(
            f"Cannot create lens from {back_surface.name} and {front_surface.name}"
        )

    def _build_bi_lens(
        self: "ToricLensBuilder",
        lens_class: Type[Union[ToricBiConcave, ToricBiConvex, ToricMeniscus]],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> Union[ToricBiConcave, ToricBiConvex, ToricMeniscus]:
        """Build bi-curved lens of class 'lens_class'.

        Parameters
        ----------
        lens_class : {ToricBiConcave, ToricBiConvex, ToricMeniscus}
        back_surface, front_surface : Toroidal

        Returns
        -------
        instance of 'lens_class'
        """

        return lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            front_curvature_vertical=self._front_curvature_vertical,
            front_curvature_horizontal=self._front_curvature_horizontal,
            back_curvature_vertical=self._back_curvature_vertical,
            back_curvature_horizontal=self._back_curvature_horizontal,
            material=self._material,
            name=self._name,
        )

    def _flip_bi_lens(
        self: "ToricLensBuilder",
        lens_class: Type[ToricMeniscus],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> ToricMeniscus:
        """Build bi-curved lens of class 'lens_class' with flipped sides.

        Parameters
        ----------
        lens_class : ToricMeniscus
        back_surface, front_surface : Toroidal

        Returns
        -------
        instance of 'lens_class'
        """

        lens = lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            front_curvature_vertical=self._back_curvature_vertical,
            front_curvature_horizontal=self._back_curvature_horizontal,
            back_curvature_vertical=self._front_curvature_vertical,
            back_curvature_horizontal=self._front_curvature_horizontal,
            material=self._material,
            name=self._name,
        )
        lens.transform = flip(lens.center_thickness)

        return lens

    def _build_plano_lens(
        self: "ToricLensBuilder",
        lens_class: Type[Union[ToricPlanoConcave, ToricPlanoConvex]],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> Union[ToricPlanoConcave, ToricPlanoConvex]:
        """Build plano-curved lens of class 'lens_class'.

        Parameters
        ----------
        lens_class : {ToricPlanoConcave, ToricPlanoConvex}
        back_surface, front_surface : Toroidal

        Returns
        -------
        instance of 'lens_class'
        """

        return lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            curvature_vertical=self._front_curvature_vertical,
            curvature_horizontal=self._front_curvature_horizontal,
            material=self._material,
            name=self._name,
        )

    def _flip_plano_lens(
        self: "ToricLensBuilder",
        lens_class: Type[Union[ToricPlanoConcave, ToricPlanoConvex]],
        back_surface: Toroidal,
        front_surface: Toroidal,
    ) -> Union[ToricPlanoConcave, ToricPlanoConvex]:
        """Build plano-curved lens of class 'lens_class' with sides flipped.

        Parameters
        ----------
        lens_class : {ToricPlanoConcave, ToricPlanoConvex}
        back_surface, front_surface : Toroidal

        Returns
        -------
        instance of 'lens_class'
        """

        lens = lens_class(
            diameter=self._diameter,
            center_thickness=self._center_thickness,
            curvature_vertical=self._back_curvature_vertical,
            curvature_horizontal=self._back_curvature_horizontal,
            material=self._material,
            name=self._name,
        )
        lens.transform = flip(lens.center_thickness)

        return lens
