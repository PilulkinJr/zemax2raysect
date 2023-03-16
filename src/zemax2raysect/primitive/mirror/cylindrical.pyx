from libc.math cimport sqrt

from raysect.core cimport AffineMatrix3D, Material, translate
from raysect.primitive import Intersect, Subtract, Sphere, Cylinder
from raysect.primitive.utility cimport EncapsulatedPrimitive

from ..surface.cylinder_segment cimport CylinderSegment


cdef class CylindricalMirror(EncapsulatedPrimitive):

    cdef:
        readonly double diameter
        readonly double curvature
        readonly double curve_thickness

    def __init__(
        self, 
        double diameter, 
        double curvature, 
        object parent=None, 
        AffineMatrix3D transform=None, 
        Material material=None, 
        str name=None
    ):

        if diameter < 0:
            raise ValueError(f"Cylindrical mirror's diameter cannot be less than or equal to zero, got {diameter}")

        if curvature < 0:
            raise ValueError(f"Cylindrical mirror's curvature cannot be less than or equal to zero, got {curvature}")

        cdef double radius = 0.5 * diameter

        if curvature < radius:
            raise ValueError(f"Cylindrical mirror's curvature cannot be less than its frame's radius, got {curvature} >= {radius}")

        self.diameter = diameter
        self.curvature = curvature
        self.curve_thickness = curvature - sqrt(curvature * curvature - radius * radius)

        curve = CylinderSegment(radius, self.curvature, self.curve_thickness)
        barrel = Cylinder(radius, self.curve_thickness)
        mirror = Intersect(curve, barrel)

        super().__init__(mirror, parent, transform, material, name)
