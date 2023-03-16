from libc.math cimport sqrt

from raysect.core cimport AffineMatrix3D, Material, translate
from raysect.primitive import Intersect, Subtract, Sphere, Cylinder
from raysect.primitive.utility cimport EncapsulatedPrimitive

from ..surface.sphere_segment cimport SphereSegment


cdef class SphericalMirror(EncapsulatedPrimitive):
    """Spherical mirror primitive.

    A mirror is formed by two concave surfaces, in a way that both curvature center lie in +z direction.
    Center of the front surface lies at z=0. Center of the back surface lies in -z direction.

    :param float diameter: Diameter of the mirror's frame.
    :param float curvature: Radius of curvature in meters.
    :param Node parent: Assigns the primitive's parent to the specified scene-graph object (default = None).
    :param AffineMatrix3D transform: Sets the affine transform associated with the primitive (default = None).
    :param Material material: An object representing the material properties of the primitive (default = None).
    :param str name: A string defining the mirror's name (default = None).
    """
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
            raise ValueError(f"Spherical mirror's diameter cannot be less than or equal to zero, got {diameter}")

        if curvature < 0:
            raise ValueError(f"Spherical mirror's curvature cannot be less than or equal to zero, got {curvature}")

        cdef double radius = 0.5 * diameter

        if curvature < radius:
            raise ValueError(f"Spherical mirror's curvature cannot be less than its frame's radius, got {curvature} >= {radius}")

        self.diameter = diameter
        self.curvature = curvature

        mirror = SphereSegment(self.diameter, self.curvature)

        super().__init__(mirror, parent, transform, material, name)
