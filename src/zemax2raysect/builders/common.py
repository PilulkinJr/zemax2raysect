"""Common things used in primitive builder classes."""
import logging
from enum import Enum
from typing import Literal, Tuple, Union

import numpy as np

from raysect.core import AffineMatrix3D, rotate_y, translate

from ..surface import Standard, Surface, Toroidal

Direction = Literal[-1, 1]
CurvatureSign = Literal[-1, 0, 1]

LOGGER = logging.getLogger(__name__)

DEFAULT_THICKNESS = 1.0e-6


class CannotCreatePrimitive(Exception):
    """Raise this exception if primitive cannot be created."""

    pass


class SurfaceType(Enum):
    """Enumerate surface types."""

    UNDETERMINED = "UNDETERMINED"
    FLAT = "FLAT"
    CYLINDRICAL = "CYLINDRICAL"
    SPHERICAL = "SPHERICAL"
    TOROIDAL = "TOROIDAL"


class ShapeType(Enum):
    """Enumerate shape types."""

    UNDETERMINED = "UNDETERMINED"
    ROUND = "ROUND"
    RECTANGULAR = "RECTANGULAR"


def determine_primitive_type(surface: Union[Standard, Toroidal]) -> Tuple[SurfaceType, ShapeType]:
    """Determine surface type and shape type for the primitive.

    Allows to interpret Standard and Toroidal surfaces as spherical or cylindrical
    based on their parameters.

    Parameters
    ----------
    surface : Surface

    Returns
    -------
    surface_type : SurfaceType
    shape_type : ShapeType
    """
    surface_type = SurfaceType.UNDETERMINED
    shape_type = ShapeType.UNDETERMINED

    if not isinstance(surface, (Standard, Toroidal)):
        return surface_type, shape_type

    # shape_type = ShapeType.RECTANGULAR if surface.aperture is not None else ShapeType.ROUND

    if surface.aperture is not None and surface.aperture_type == 'rectangular':
        shape_type = ShapeType.RECTANGULAR
    else:
        shape_type = ShapeType.ROUND

    if isinstance(surface, Standard):
        # Standard surface type could only denote a flat or spherical surface
        surface_type = SurfaceType.FLAT if surface.radius == 0 else SurfaceType.SPHERICAL

    if isinstance(surface, Toroidal):

        rv = abs(surface.radius)
        rh = abs(surface.radius_horizontal)
        equal = abs(rv - rh) < 1.0e-8

        # both radii are zero -- flat surface
        if rv == 0 and rh == 0:
            surface_type = SurfaceType.FLAT

        # both radii are not zero and not equal to each other -- toroidal surface
        elif (rv != 0) and (rh != 0) and not equal:
            surface_type = SurfaceType.TOROIDAL

        # both radii are not zero and equal to each other -- spherical surface
        elif (rv != 0) and (rh != 0) and equal:
            surface_type = SurfaceType.SPHERICAL

        # one of radii is zero -- cylindrical surface
        elif (rv != 0 and rh == 0) or (rv == 0 and rh != 0):
            surface_type = SurfaceType.CYLINDRICAL

    return surface_type, shape_type


def flip(thickness: float) -> AffineMatrix3D:
    """Flip back and front sides of the primitive.

    Parameters
    ----------
    thickness : float
        Thickness of the primitive along its z axis.

    Returns
    -------
    AffineMatrix3D
    """
    # equivalent to this:
    # return rotate_y(180.0) * translate(0.0, 0.0, -thickness)

    m = AffineMatrix3D()
    m[0, 0] = -1.0
    m[2, 2] = -1.0
    m[2, 3] = thickness
    return m


def transform_according_to_direction(
    mirror: object,
    direction: Direction,
    curvature_sign: CurvatureSign,
) -> AffineMatrix3D:
    """Calculate a transformation for a mirror to account for Zemax' ray propagation direction.

    Parameters
    ----------
    mirror : SphericalMirror or ToricMirror
        Mirror primitive.
    direction : {-1, 1}
        Ray propagation direction.
    curvature_sign : {-1, 0, 1}
        Curvature sign of the mirror's surface.

    Returns
    -------
    AffineMatrix3D
    """
    if direction == 1 and curvature_sign == 1:
        LOGGER.debug("Shifting mirror %s along its axis", mirror.name)
        return translate(0, 0, mirror.center_thickness)

    if direction == 1 and curvature_sign == -1:
        LOGGER.debug("Rotating mirror %s around y axis", mirror.name)
        return rotate_y(180)

    LOGGER.debug("Additional transformation is not required")
    return AffineMatrix3D()


def sign(x: float) -> int:
    return np.sign(x).astype(int)


def determine_curvature_signs(
    back_surface: Surface, front_surface: Surface
) -> Tuple[CurvatureSign, CurvatureSign]:
    """Determine curvature signs of the both lens surfaces.

    Sign convention is:
        -1 -- curvature center is behind the surface
        1 -- curvature center is in front of the surface
        0 -- curvature radius is 0 (flat surface)

    Parameters
    ----------
    back_surface : Surface
    front_surface : Surface

    Returns
    -------
    (int, int)
    """
    if not isinstance(back_surface, (Standard, Toroidal)):
        raise TypeError(
            f"back_surface has to be Standard or Toroidal type, got {type(back_surface)}"
        )

    if not isinstance(front_surface, (Standard, Toroidal)):
        raise TypeError(
            f"front_surface has to be Standard or Toroidal type, got {type(front_surface)}"
        )

    back_sgn = sign(back_surface.radius)
    front_sgn = sign(back_surface.radius)

    return back_sgn, front_sgn
