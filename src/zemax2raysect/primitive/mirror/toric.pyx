from libc.math cimport sqrt

from raysect.core cimport AffineMatrix3D, Material, translate, rotate_z
from raysect.primitive import Intersect, Subtract, Sphere, Cylinder
from raysect.primitive.utility cimport EncapsulatedPrimitive

from ..surface.torus_segment cimport TorusSegment


cdef class ToricMirror(EncapsulatedPrimitive):

    cdef:
        readonly double diameter
        readonly double vertical_curvature
        readonly double horizontal_curvature

    def __init__(
        self,
        double diameter,
        double vertical_curvature,
        double horizontal_curvature,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None,
    ):

        if diameter <= 0:
            raise ValueError(f"Toric mirror's diameter has to be positive, got {diameter}.")

        if vertical_curvature <= 0:
            raise ValueError(
                f"Toric mirror's vertical curvature has to be positive, got {vertical_curvature}."
            )

        if horizontal_curvature <= 0:
            raise ValueError(
                f"Toric mirror's horizontal curvature has to be positive, got {horizontal_curvature}."
            )

        if vertical_curvature == horizontal_curvature:
            raise ValueError(
                "Toric mirror's vertical curvature has to differ from horizontal curvature."
            )

        cdef double radius = 0.5 * diameter

        if vertical_curvature < radius:
            raise ValueError(
                "Mirror's vertical curvature cannot be less than its radius"
                f", got {vertical_curvature} > {radius}."
            )

        if horizontal_curvature < radius:
            raise ValueError(
                "Mirror's horizontal curvature cannot be less its radius"
                f", got {horizontal_curvature} > {radius}."
            )

        self.diameter = diameter
        self.vertical_curvature = vertical_curvature
        self.horizontal_curvature = horizontal_curvature

        cdef double radius_minor = vertical_curvature
        cdef double radius_major = horizontal_curvature - vertical_curvature
        cdef double height = vertical_curvature - sqrt(vertical_curvature * vertical_curvature - radius * radius)
        cdef AffineMatrix3D _rotation = AffineMatrix3D()

        if vertical_curvature > horizontal_curvature:
            radius_minor = horizontal_curvature
            radius_major = vertical_curvature - horizontal_curvature
            height = horizontal_curvature - sqrt(
                horizontal_curvature * horizontal_curvature - radius * radius
            )
            _rotation = rotate_z(90)

        curve = TorusSegment(
            radius_major,
            radius_minor,
            height,
            transform=_rotation,
        )

        barrel = Cylinder(radius, height)

        mirror = Intersect(curve, barrel)

        super().__init__(mirror, parent, transform, material, name)
