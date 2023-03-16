from raysect.primitive import Intersect, Subtract, Union, Sphere, Cylinder

from raysect.core cimport Primitive
from raysect.core cimport AffineMatrix3D, translate, Material
from raysect.primitive.utility cimport EncapsulatedPrimitive
from libc.math cimport sqrt


DEF PADDING = 0.000001


cdef class Meniscus(EncapsulatedPrimitive):
    """
    A meniscus spherical lens primitive.

    A lens consisting of a concave and a convex spherical surface aligned on a
    common axis. The two surfaces sit at either end of a cylindrical barrel
    that is aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is concave, it is the negative surface most on the z-axis. The
    front surface is convex, it is the positive most surface on the z-axis. The
    centre of the back surface lies on z=0 and with the lens extending along
    the +ve z direction.

    :param diameter: The diameter of the lens body.
    :param center_thickness: The thickness of the lens measured along the lens axis.
    :param front_curvature: The radius of curvature of the front (convex) surface.
    :param back_curvature: The radius of curvature of the back (concave) surface.
    :param parent: Assigns the Node's parent to the specified scene-graph object.
    :param transform: Sets the affine transform associated with the Node.
    :param material: An object representing the material properties of the primitive.
    :param name: A string defining the node name.
    """
    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double edge_thickness
        readonly double front_thickness
        readonly double back_thickness
        readonly double front_curvature
        readonly double back_curvature

    def __init__(self, double diameter, double center_thickness, double front_curvature, double back_curvature, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.front_curvature = front_curvature
        self.back_curvature = back_curvature

        # validate
        if diameter <= 0:
            raise ValueError("The lens diameter must be greater than zero.")

        if center_thickness <= 0:
            raise ValueError("The lens thickness must be greater than zero.")

        radius = 0.5 * diameter

        if front_curvature < radius:
            raise ValueError("The radius of curvature of the front face cannot be less than the barrel radius.")

        if back_curvature < radius:
            raise ValueError("The radius of curvature of the back face cannot be less than the barrel radius.")

        self._calc_geometry()

        # if self.edge_thickness < 0:
        #     raise ValueError("The curvatures and/or thickness are not compatible with the specified diameter.")

        # construct lens
        if self._is_short():
            lens = self._build_short_lens()
        else:
            lens = self._build_long_lens()

        # attach to local root (performed in EncapsulatedPrimitive init)
        super().__init__(lens, parent, transform, material, name)

    cdef void _calc_geometry(self):

        cdef double radius, radius_sqr

        # barrel radius
        radius = 0.5 * self.diameter
        radius_sqr = radius * radius

        # thickness of spherical surfaces
        self.front_thickness = self.front_curvature - sqrt(self.front_curvature * self.front_curvature - radius_sqr)
        self.back_thickness = self.back_curvature - sqrt(self.back_curvature * self.back_curvature - radius_sqr)

        # edge thickness is the length of the barrel without the front surface
        self.edge_thickness = self.center_thickness - self.front_thickness + self.back_thickness

    cdef bint _is_short(self):
        """
        Does the front sphere have sufficient radius to build the lens with just an intersection?        
        """

        cdef double available_thickness = 2 * self.front_curvature - self.front_thickness
        return (self.center_thickness + self.back_thickness) <= available_thickness

    cdef Primitive _build_short_lens(self):
        """
        Short lens requires 3 primitives.
        """

        # padding to add to the barrel cylinder to avoid potential numerical accuracy issues
        padding = (self.back_thickness + self.center_thickness) * PADDING

        # construct lens using CSG
        front = Sphere(self.front_curvature, transform=translate(0, 0, self.center_thickness - self.front_curvature))
        back = Sphere(self.back_curvature, transform=translate(0, 0, -self.back_curvature))
        barrel = Cylinder(0.5 * self.diameter, self.back_thickness + self.center_thickness + padding, transform=translate(0, 0, -self.back_thickness))
        return Subtract(Intersect(barrel, front), back)

    cdef Primitive _build_long_lens(self):
        """
        Long lens requires 4 primitives.
        """

        # padding to avoid potential numerical accuracy issues
        padding = (self.back_thickness + self.center_thickness) * PADDING
        radius = 0.5 * self.diameter

        # front face
        front_sphere = Sphere(self.front_curvature, transform=translate(0, 0, self.center_thickness - self.front_curvature))
        front_barrel = Cylinder(radius, self.front_thickness + 2 * padding, transform=translate(0, 0, self.center_thickness - self.front_thickness - padding))
        front_element = Intersect(front_sphere, front_barrel)

        # back face
        back_element = Sphere(self.back_curvature, transform=translate(0, 0, -self.back_curvature))

        # barrel
        barrel = Cylinder(radius, self.edge_thickness, transform=translate(0, 0, -self.back_thickness))

        # construct lens
        return Subtract(Union(barrel, front_element), back_element)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return Meniscus(self.diameter, self.center_thickness, self.front_curvature, self.back_curvature, parent, transform, material, name)
