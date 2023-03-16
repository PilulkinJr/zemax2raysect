from raysect.core cimport Primitive
from raysect.core cimport AffineMatrix3D, translate, Material, rotate_y
from raysect.primitive import Intersect, Subtract, Union, Cylinder
from raysect.primitive.utility cimport EncapsulatedPrimitive
from libc.math cimport sqrt

DEF PADDING = 0.000001


cdef class CylindricalBiConvex(EncapsulatedPrimitive):
    """
    A bi-convex cylindrical lens primitive.

    A lens consisting of two convex cylindrical surfaces with axes
    parallel to each other and y-axis. The two surfaces sit at either
    end of a cylindrical barrel that is aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the negative surface most on the z-axis, while the front
    surface is the positive most surface on the z-axis. The centre of the back
    surface lies on z=0 and with the lens extending along the +ve z direction.

    :param diameter: The diameter of the lens body.
    :param center_thickness: The thickness of the lens measured along the lens axis.
    :param front_curvature: The radius of curvature of the front surface.
    :param back_curvature: The radius of curvature of the back surface.
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

    def __init__(
        self,
        double diameter,
        double center_thickness,
        double front_curvature,
        double back_curvature,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None,
    ):

        # validate
        if diameter <= 0:
            raise ValueError("The lens diameter must be greater than zero.")

        if center_thickness <= 0:
            raise ValueError("The lens thickness must be greater than zero.")

        radius = 0.5 * diameter

        if front_curvature < radius:
            msg = "The radius of curvature of the front face cannot be less than the barrel radius, " f"got {front_curvature} < {radius}"
            raise ValueError(msg)

        if back_curvature < radius:
            raise ValueError("The radius of curvature of the back face cannot be less than the barrel radius.")

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.front_curvature = front_curvature
        self.back_curvature = back_curvature

        self._calc_geometry()

        if self.edge_thickness < 0:
            raise ValueError("The curvatures and/or thickness are too small to produce a lens of the specified diameter.")

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

        # edge thickness is the length of the barrel without the curved surfaces
        self.edge_thickness = self.center_thickness - (self.front_thickness + self.back_thickness)

    cdef bint _is_short(self):
        """Do the facing cylinders overlap sufficiently to build a lens using just their intersection?"""

        cdef double available_thickness = min(
            2 * (self.front_curvature - self.front_thickness),
            2 * (self.back_curvature - self.back_thickness)
        )
        return self.edge_thickness <= available_thickness

    cdef Primitive _build_short_lens(self):
        """
        Short lens requires 3 primitives.
        """

        # padding to add to the barrel cylinder to avoid potential numerical accuracy issues
        padding = self.center_thickness * PADDING
        radius = 0.5 * self.diameter

        # construct lens using CSG
        front = Cylinder(
            self.front_curvature,
            self.diameter,
            transform=translate(-radius, 0, self.center_thickness - self.front_curvature) * rotate_y(90)
        )
        back = Cylinder(
            self.back_curvature,
            self.diameter,
            transform=translate(-radius, 0, self.back_curvature) * rotate_y(90)
        )
        barrel = Cylinder(
            radius,
            self.center_thickness + 2 * padding,
            transform=translate(0, 0, -padding)
        )
        return Intersect(barrel, Intersect(front, back))

    cdef Primitive _build_long_lens(self):
        """
        Long lens requires 5 primitives.
        """

        # padding to avoid potential numerical accuracy issues
        padding = self.center_thickness * PADDING
        radius = 0.5 * self.diameter

        # front face
        front_face = Cylinder(
            self.front_curvature,
            self.diameter,
            transform=translate(-radius, 0, self.center_thickness - self.front_curvature) * rotate_y(90)
        )
        front_barrel = Cylinder(
            radius,
            self.front_thickness + 2 * padding,
            transform=translate(0, 0, self.back_thickness + self.edge_thickness - padding)
        )
        front_element = Intersect(front_face, front_barrel)

        # back face
        back_face = Cylinder(
            self.back_curvature,
            self.diameter,
            transform=translate(-radius, 0, self.back_curvature) * rotate_y(90)
        )
        back_barrel = Cylinder(
            radius,
            self.back_thickness + 2 * padding,
            transform=translate(0, 0, -padding)
        )
        back_element = Intersect(back_face, back_barrel)

        # bridging barrel
        barrel = Cylinder(radius, self.edge_thickness, transform=translate(0, 0, self.back_thickness))

        # construct lens
        return Union(barrel, Union(front_element, back_element))

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return CylindricalBiConvex(self.diameter, self.center_thickness, self.front_curvature, self.back_curvature, parent, transform, material, name)


cdef class CylindricalBiConcave(EncapsulatedPrimitive):
    """
    A bi-concave cylindrical lens primitive.

    A lens consisting of two convex cylindrical surfaces with axes
    parallel to each other and y-axis. The two surfaces sit at either
    end of a cylindrical barrel that is aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the negative surface most on the z-axis, while the front
    surface is the positive most surface on the z-axis. The centre of the back
    surface lies on z=0 and with the lens extending along the +ve z direction.

    :param diameter: The diameter of the lens body.
    :param center_thickness: The thickness of the lens measured along the lens axis.
    :param front_curvature: The radius of curvature of the front surface.
    :param back_curvature: The radius of curvature of the back surface.
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

    def __init__(
        self,
        double diameter,
        double center_thickness,
        double front_curvature,
        double back_curvature,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):
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

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.front_curvature = front_curvature
        self.back_curvature = back_curvature

        self._calc_geometry()

        cdef double padding = radius * PADDING

        # construct lens using CSG
        front = Cylinder(
            self.front_curvature,
            self.diameter + 2 * padding,
            transform=translate(-(radius + padding), 0, self.center_thickness + self.front_curvature) * rotate_y(90)
        )
        back = Cylinder(
            self.back_curvature,
            self.diameter + 2 * padding,
            transform=translate(-(radius + padding), 0, -self.back_curvature) * rotate_y(90)
        )
        barrel = Cylinder(
            radius,
            self.edge_thickness,
            transform=translate(0, 0, -self.back_thickness)
        )
        lens = Subtract(Subtract(barrel, front), back)

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

        # edge thickness is the length of the barrel without the curved surfaces
        self.edge_thickness = self.center_thickness + self.front_thickness + self.back_thickness

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return CylindricalBiConcave(self.diameter, self.center_thickness, self.front_curvature, self.back_curvature, parent, transform, material, name)


cdef class CylindricalPlanoConvex(EncapsulatedPrimitive):
    """
    A plano-convex cylindrical lens primitive.

    A lens consisting of a convex cylindrical surface with the axis
    parallel to y-axis and a plane (flat) surface. The two surfaces sit
    at either end of a cylindrical barrel that is aligned to lie along
    the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the plane surface, it is the negative surface most on the
    z-axis. The front surface is the spherical surface, it is the positive most
    surface on the z-axis. The back (plane) surface lies on z=0 with the lens
    extending along the +ve z direction.

    :param diameter: The diameter of the lens body.
    :param center_thickness: The thickness of the lens measured along the lens axis.
    :param curvature: The radius of curvature of the spherical front surface.
    :param parent: Assigns the Node's parent to the specified scene-graph object.
    :param transform: Sets the affine transform associated with the Node.
    :param material: An object representing the material properties of the primitive.
    :param name: A string defining the node name.
    :return:
    """

    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double edge_thickness
        readonly double curve_thickness
        readonly double curvature

    def __init__(
        self,
        double diameter,
        double center_thickness,
        double curvature,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):
        # validate
        if diameter <= 0:
            raise ValueError("The lens diameter must be greater than zero.")

        if center_thickness <= 0:
            raise ValueError("The lens thickness must be greater than zero.")

        cdef double radius = 0.5 * diameter

        if curvature < radius:
            raise ValueError("The radius of curvature of the face cannot be less than the barrel radius.")

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.curvature = curvature

        self._calc_geometry()

        if self.edge_thickness < 0:
            raise ValueError("The curvature and/or thickness is too small to produce a lens of the specified diameter.")

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
        self.curve_thickness = self.curvature - sqrt(self.curvature * self.curvature - radius_sqr)

        # edge thickness is the length of the barrel without the curved surfaces
        self.edge_thickness = self.center_thickness - self.curve_thickness

    cdef bint _is_short(self):
        """Does the front cylinder have sufficient radius to build the lens with just an intersection?"""

        cdef double available_thickness = 2 * (self.curvature - self.curve_thickness)
        return self.edge_thickness <= available_thickness

    cdef Primitive _build_short_lens(self):
        """Short lens requires 2 primitives."""

        # padding to add to the barrel cylinder to avoid potential numerical accuracy issues
        cdef double padding = self.center_thickness * PADDING
        cdef double radius = 0.5 * self.diameter

        # construct lens using CSG
        front = Cylinder(
            self.curvature,
            self.diameter,
            transform=translate(-radius, 0, self.center_thickness - self.curvature) * rotate_y(90)
        )
        barrel = Cylinder(radius, self.center_thickness + padding)
        return Intersect(barrel, front)

    cdef Primitive _build_long_lens(self):
        """Long lens requires 3 primitives."""

        # padding to avoid potential numerical accuracy issues
        cdef double padding = self.center_thickness * PADDING
        cdef double radius = 0.5 * self.diameter

        # curved face
        curved_cylinder = Cylinder(
            self.curvature,
            self.diameter,
            transform=translate(-radius, 0, self.center_thickness - self.curvature) * rotate_y(90)
        )
        curved_barrel = Cylinder(
            radius, 
            self.curve_thickness + 2 * padding, 
            transform=translate(0, 0, self.edge_thickness - padding)
        )
        curved_element = Intersect(curved_cylinder, curved_barrel)

        # barrel
        barrel = Cylinder(radius, self.edge_thickness)

        # construct lens
        return Union(barrel, curved_element)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return CylindricalPlanoConvex(self.diameter, self.center_thickness, self.curvature, parent, transform, material, name)


cdef class CylindricalPlanoConcave(EncapsulatedPrimitive):
    """
    A plano-concave cylindrical lens primitive.

    A lens consisting of a convex cylindrical surface with the axis
    parallel to y-axis and a plane (flat) surface. The two surfaces sit
    at either end of a cylindrical barrel that is aligned to lie along
    the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the plane surface, it is the negative surface most on the
    z-axis. The front surface is the spherical surface, it is the positive most
    surface on the z-axis. The back (plane) surface lies on z=0 with the lens
    extending along the +ve z direction.

    :param diameter: The diameter of the lens body.
    :param center_thickness: The thickness of the lens measured along the lens axis.
    :param curvature: The radius of curvature of the spherical front surface.
    :param parent: Assigns the Node's parent to the specified scene-graph object.
    :param transform: Sets the affine transform associated with the Node.
    :param material: An object representing the material properties of the primitive.
    :param name: A string defining the node name.
    :return:
    """

    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double edge_thickness
        readonly double curve_thickness
        readonly double curvature

    def __init__(
        self,
        double diameter,
        double center_thickness,
        double curvature,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):
        # validate
        if diameter <= 0:
            raise ValueError("The lens diameter must be greater than zero.")

        if center_thickness <= 0:
            raise ValueError("The lens thickness must be greater than zero.")

        radius = 0.5 * diameter

        if curvature < radius:
            raise ValueError("The radius of curvature of the face cannot be less than the barrel radius.")

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.curvature = curvature

        self._calc_geometry()

        cdef double padding = radius * PADDING

        # construct lens using CSG
        curve = Cylinder(
            self.curvature,
            self.diameter + 2 * padding,
            transform=translate(-(radius + padding), 0, self.center_thickness + self.curvature) * rotate_y(90)
        )
        barrel = Cylinder(radius, self.edge_thickness)
        lens = Subtract(barrel, curve)

        # attach to local root (performed in EncapsulatedPrimitive init)
        super().__init__(lens, parent, transform, material, name)

    cdef void _calc_geometry(self):

        cdef double radius, radius_sqr

        # barrel radius
        radius = 0.5 * self.diameter
        radius_sqr = radius * radius

        # thickness of spherical surfaces
        self.curve_thickness = self.curvature - sqrt(self.curvature * self.curvature - radius_sqr)

        # edge thickness is the length of the barrel without the curved surfaces
        self.edge_thickness = self.center_thickness + self.curve_thickness

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return CylindricalPlanoConcave(self.diameter, self.center_thickness, self.curvature, parent, transform, material, name)


cdef class CylindricalMeniscus(EncapsulatedPrimitive):
    """
    A meniscus cylindrical lens primitive.

    A lens consisting of a concave and a convex cylindrical surfaces
    with axes parallel to each other and y-axis. The two surfaces sit at
    either end of a cylindrical barrel that is aligned to lie along the
    z-axis.

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

    def __init__(
        self,
        double diameter,
        double center_thickness,
        double front_curvature,
        double back_curvature,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):

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

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.front_curvature = front_curvature
        self.back_curvature = back_curvature

        self._calc_geometry()

        if self.edge_thickness < 0:
            raise ValueError("The curvatures and/or thickness are not compatible with the specified diameter.")

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
        """Does the front cylinder have sufficient radius to build the lens with just an intersection?"""

        cdef double available_thickness = 2 * self.front_curvature - self.front_thickness
        return (self.center_thickness + self.back_thickness) <= available_thickness

    cdef Primitive _build_short_lens(self):
        """Short lens requires 3 primitives."""
        cdef double radius, padding

        radius = 0.5 * self.diameter

        # padding to add to the barrel cylinder to avoid potential numerical accuracy issues
        padding = (self.back_thickness + self.center_thickness) * PADDING

        # construct lens using CSG
        front = Cylinder(
            self.front_curvature,
            self.diameter,
            transform=translate(-radius, 0, self.center_thickness - self.front_curvature) * rotate_y(90)
        )
        back = Cylinder(
            self.back_curvature,
            self.diameter,
            transform=translate(-radius, 0, -self.back_curvature) * rotate_y(90)
        )
        barrel = Cylinder(
            radius,
            self.back_thickness + self.center_thickness + padding,
            transform=translate(0, 0, -self.back_thickness),
        )
        return Subtract(Intersect(barrel, front), back)

    cdef Primitive _build_long_lens(self):
        """Long lens requires 4 primitives."""
        cdef double radius, padding

        radius = 0.5 * self.diameter

        # padding to avoid potential numerical accuracy issues
        padding = (self.back_thickness + self.center_thickness) * PADDING

        # front face
        front_face = Cylinder(
            self.front_curvature,
            self.diameter,
            transform=translate(-radius, 0, self.center_thickness - self.front_curvature) * rotate_y(90)
        )
        front_barrel = Cylinder(
            radius,
            self.front_thickness + 2 * padding,
            transform=translate(0, 0, self.center_thickness - self.front_thickness - padding)
        )
        front_element = Intersect(front_face, front_barrel)

        # back face
        back_element = Cylinder(
            self.back_curvature,
            self.diameter,
            transform=translate(-radius, 0, -self.back_curvature) * rotate_y(90)
        )

        # barrel
        barrel = Cylinder(radius, self.edge_thickness, transform=translate(0, 0, -self.back_thickness))

        # construct lens
        return Subtract(Union(barrel, front_element), back_element)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return CylindricalMeniscus(self.diameter, self.center_thickness, self.front_curvature, self.back_curvature, parent, transform, material, name)
