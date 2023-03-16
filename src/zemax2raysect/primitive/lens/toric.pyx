from libc.math cimport sqrt

from raysect.core cimport AffineMatrix3D, Material, translate, rotate_z, rotate_y, Primitive
from raysect.primitive import Intersect, Subtract, Cylinder, Union
from raysect.primitive.utility cimport EncapsulatedPrimitive

from ..torus import Toric

DEF PADDING = 1.0e-6

# avoid numerical inaccuracies
cdef AffineMatrix3D ROTATE_Y180 = AffineMatrix3D(
    [
        [-1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, -1, 0],
        [0, 0, 0, 1],
    ]
)


cpdef void _check_lens_parameters(object lens) except *:
    """Check parameters of a lens with two toric surfaces.

    Setting *_curvature_vertical and *_curvature_horizontal to the same value leads to errors.
    Use appropriate spherical lens primitive in that case.
    """

    cdef double radius = 0.5 * lens.diameter

    if lens.diameter <= 0:
        raise ValueError(f"Lens diameter must be positive, got {lens.diameter}")

    if lens.center_thickness <= 0:
        raise ValueError(f"Lens center thickness must be positive, got {lens.center_thickness}")

    if lens.front_curvature_vertical <= 0:
        raise ValueError(f"Lens front vertical curvature radius must be positive, got {lens.front_curvature_vertical}")

    if lens.front_curvature_vertical < radius:
        raise ValueError(f"Lens front vertical curvature radius must be greater than barrel radius, got {lens.front_curvature_vertical} < {radius}")

    if lens.front_curvature_horizontal <= 0:
        raise ValueError(f"Lens front horizontal curvature radius must be positive, got {lens.front_curvature_horizontal}")

    if lens.front_curvature_horizontal < radius:
        raise ValueError(f"Lens front horizontal curvature radius must be greater than barrel radius, got {lens.front_curvature_horizontal} < {radius}")

    if lens.back_curvature_vertical <= 0:
        raise ValueError(f"Lens back vertical curvature radius must be positive, got {lens.back_curvature_vertical}")

    if lens.back_curvature_vertical < radius:
        raise ValueError(f"Lens back vertical curvature radius must be greater than barrel radius, got {lens.back_curvature_vertical} < {radius}")

    if lens.back_curvature_horizontal <= 0:
        raise ValueError(f"Lens back horizontal curvature radius must be positive, got {lens.back_curvature_horizontal}")

    if lens.back_curvature_horizontal < radius:
        raise ValueError(f"Lens back horizontal curvature radius must be greater than barrel radius, got {lens.back_curvature_horizontal} < {radius}")


cdef void _calculate_toric_geometry(
    double diameter,
    double curvature_vertical,
    double curvature_horizontal,
    double *radius_major,
    double *radius_minor,
    double *thickness,
    double *rotation_angle,
) except *:
    """Calculate geometry of a toric lens face.

    :param double diameter: Lens barrel diameter.
    :param double curvature_vertical: Curvature radius in Y-Z plane.
    :param double curvature_horizontal: Curvature radius in X-Z plane.
    :param double *radius_major: Output major radius of a torus forming this face.
    :param double *radius_minor: Output minor radius of a torus forming this face.
    :param double *thickness: Output curve thickness of this face.
    :param double *rotation_angle: Output rotation angle around Z-axis.
    """
    if curvature_vertical == curvature_horizontal:

        msg = "'curvature_vertical' and 'curvature_horizontal' must be different"
        raise ValueError(msg)

    if curvature_vertical < curvature_horizontal:

        radius_minor[0] = curvature_vertical
        radius_major[0] = curvature_horizontal - curvature_vertical
        rotation_angle[0] = 0.0

    if curvature_vertical > curvature_horizontal:

        radius_minor[0] = curvature_horizontal
        radius_major[0] = curvature_vertical - curvature_horizontal
        rotation_angle[0] = 90.0

    cdef double radius = 0.5 * diameter
    thickness[0] = radius_minor[0] - sqrt(radius_minor[0] * radius_minor[0] - radius * radius)


cdef class ToricBiConvex(EncapsulatedPrimitive):
    """A bi-convex toric lens primitive.

    A lens consisting of two convex toric surfaces aligned on a common
    axis. The two surfaces sit at either end of a cylindrical barrel that is
    aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the negative surface most on the z-axis, while the front
    surface is the positive most surface on the z-axis. The centre of the back
    surface lies on z=0 and with the lens extending along the +ve z direction.

    Attributes
    ----------
    diameter : double
        The diameter of the lens frame.
    center_thickness : double
        The thickness of the lens along the lens axis.
    front_curvature_vertical : double
        Curvature radius of the front face in the Y-Z plane.
    front_curvature_horizontal : double
        Curvature radius of the front face in the X-Y plane.
    back_curvature_vertical : double
        Curvature radius of the back face in the Y-Z plane.
    back_curvature_horizontal : double
        Curvature radius of the back face in the X-Y plane.
    parent : object
        Assigns the Node's parent to the specified scene-graph object.
    transform : AffineMatrix3D
        Sets the affine transform associated with the primitive.
    material : Material
        An object representing the material properties of the primitive.
    name : str
        A string defining the primitive's name.
    """
    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double front_curvature_vertical
        readonly double front_curvature_horizontal
        readonly double back_curvature_vertical
        readonly double back_curvature_horizontal
        readonly double front_radius_major
        readonly double front_radius_minor
        readonly double back_radius_major
        readonly double back_radius_minor
        readonly double front_thickness
        readonly double back_thickness
        readonly double edge_thickness
        readonly double front_rotation_angle
        readonly double back_rotation_angle

    def __init__(
        self, 
        double diameter,
        double center_thickness,
        double front_curvature_vertical,
        double front_curvature_horizontal,
        double back_curvature_vertical,
        double back_curvature_horizontal,
        object parent=None, 
        AffineMatrix3D transform=None, 
        Material material=None, 
        str name=None,
    ):
        """Initialize a new toric bi-convex lens.

        Parameters
        ----------
        diameter : float
            The diameter of the lens frame.
        center_thickness : float
            The thickness of the lens along the lens axis.
        front_curvature_vertical : float
            Curvature radius of the front face in the Y-Z plane.
        front_curvature_horizontal : float
            Curvature radius of the front face in the X-Y plane.
        back_curvature_vertical : float
            Curvature radius of the back face in the Y-Z plane.
        back_curvature_horizontal : float
            Curvature radius of the back face in the X-Y plane.
        parent : object
            Assigns the Node's parent to the specified scene-graph object.
        transform : AffineMatrix3D
            Sets the affine transform associated with the primitive.
        material : Material
            An object representing the material properties of the primitive.
        name : str
            A string defining the primitive's name.

        Raises
        ------
        ValueError
            If vertical curvature == horizontal curvature for any of the lens faces.
        """
        self.diameter = diameter
        self.center_thickness = center_thickness
        self.back_curvature_vertical = back_curvature_vertical
        self.back_curvature_horizontal = back_curvature_horizontal
        self.front_curvature_vertical = front_curvature_vertical
        self.front_curvature_horizontal = front_curvature_horizontal

        _check_lens_parameters(self)
        self._calculate_geometry()

        if self.is_short():
            lens = self._build_short_lens()
        else:
            lens = self._build_long_lens()

        super().__init__(lens, parent, transform, material, name)

    cdef void _calculate_geometry(self) except *:
        """Calculate geometry for both lens' faces."""
        _calculate_toric_geometry(
            self.diameter,
            self.back_curvature_vertical,
            self.back_curvature_horizontal,
            &self.back_radius_major,
            &self.back_radius_minor,
            &self.back_thickness,
            &self.back_rotation_angle,
        )

        _calculate_toric_geometry(
            self.diameter,
            self.front_curvature_vertical,
            self.front_curvature_horizontal,
            &self.front_radius_major,
            &self.front_radius_minor,
            &self.front_thickness,
            &self.front_rotation_angle,
        )

        self.edge_thickness = self.center_thickness - (self.front_thickness + self.back_thickness)

        if self.edge_thickness < 0:
            msg = f"Lens curvature radii and/or diameter values lead to negative edge thickness: {self.edge_thickness}"
            raise ValueError()

    cpdef bint is_short(self):
        """Do the facing toric segments overlap sufficiently to build a lens using just their intersection?"""

        cdef double available_thickness = (
            self.front_radius_minor - self.front_thickness
            + self.back_radius_minor - self.back_thickness
        )

        return self.edge_thickness < available_thickness

    cdef Primitive _build_short_lens(self):

        cdef:
            double radius = 0.5 * self.diameter
            double padding = self.center_thickness * PADDING

        front_face = Toric(
            self.front_radius_major,
            self.front_radius_minor,
            self.front_radius_minor,
            transform = (
                rotate_z(self.front_rotation_angle)
                * translate(0, 0, -self.front_radius_minor + self.center_thickness)
            ),
        )

        front_barrel = Cylinder(
            radius,
            self.front_thickness + self.edge_thickness + padding,
            transform=translate(0, 0, self.back_thickness),
        )

        front_element = Intersect(front_face, front_barrel)

        back_face = Toric(
            self.back_radius_major,
            self.back_radius_minor,
            self.back_radius_minor,
            transform = (
                rotate_z(self.back_rotation_angle)
                * translate(0, 0, self.back_radius_minor)
                * ROTATE_Y180
            ),
        )

        back_barrel = Cylinder(
            radius,
            self.back_thickness + self.edge_thickness + padding,
            transform=translate(0, 0, -padding),
        )

        back_element = Intersect(back_face, back_barrel)

        barrel = Cylinder(
            radius,
            self.center_thickness + 2 * padding,
            transform=translate(0, 0, -padding),
        )

        return Intersect(Union(front_element, back_element), barrel)

    cdef Primitive _build_long_lens(self):

        cdef:
            double radius = 0.5 * self.diameter
            double padding = self.center_thickness * PADDING

        front_face = Toric(
            self.front_radius_major,
            self.front_radius_minor,
            self.front_radius_minor,
            transform = (
                rotate_z(self.front_rotation_angle)
                * translate(0, 0, -self.front_radius_minor + self.center_thickness)
            ),
        )

        front_barrel = Cylinder(
            radius,
            self.edge_thickness,
            transform=translate(0, 0, self.back_thickness),
        )

        front_element = Union(front_face, front_barrel)

        back_face = Toric(
            self.back_radius_major,
            self.back_radius_minor,
            self.back_radius_minor,
            transform = (
                rotate_z(self.back_rotation_angle)
                * translate(0, 0, self.back_radius_minor)
                * ROTATE_Y180
            ),
        )

        back_barrel = Cylinder(
            radius,
            self.edge_thickness,
            transform=translate(0, 0, self.back_thickness),
        )

        back_element = Union(back_face, back_barrel)

        barrel = Cylinder(
            radius,
            self.center_thickness + 2 * padding,
            transform=translate(0, 0, -padding),
        )

        return Intersect(Union(front_element, back_element), barrel)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return ToricBiConvex(
            self.diameter,
            self.center_thickness,
            self.front_curvature_vertical,
            self.front_curvature_horizontal,
            self.back_curvature_vertical,
            self.back_curvature_horizontal,
            parent,
            transform,
            material,
            name
        )


cdef class ToricBiConcave(EncapsulatedPrimitive):
    """A bi-concave toric lens primitive.

    A lens consisting of two concave toric surfaces aligned on a common
    axis. The two surfaces sit at either end of a cylindrical barrel that is
    aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the negative surface most on the z-axis, while the front
    surface is the positive most surface on the z-axis. The centre of the back
    surface lies on z=0 and with the lens extending along the +ve z direction.

    Attributes
    ----------
    diameter : double
        The diameter of the lens frame.
    center_thickness : double
        The thickness of the lens along the lens axis.
    front_curvature_vertical : double
        Curvature radius of the front face in the Y-Z plane.
    front_curvature_horizontal : double
        Curvature radius of the front face in the X-Y plane.
    back_curvature_vertical : double
        Curvature radius of the back face in the Y-Z plane.
    back_curvature_horizontal : double
        Curvature radius of the back face in the X-Y plane.
    parent : object
        Assigns the Node's parent to the specified scene-graph object.
    transform : AffineMatrix3D
        Sets the affine transform associated with the primitive.
    material : Material
        An object representing the material properties of the primitive.
    name : str
        A string defining the primitive's name.
    """
    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double back_curvature_vertical
        readonly double back_curvature_horizontal
        readonly double front_curvature_vertical
        readonly double front_curvature_horizontal
        readonly double back_radius_major
        readonly double back_radius_minor
        readonly double front_radius_major
        readonly double front_radius_minor
        readonly double back_thickness
        readonly double front_thickness
        readonly double back_rotation_angle
        readonly double front_rotation_angle
        readonly double edge_thickness

    def __init__(
        self, 
        double diameter,
        double center_thickness,
        double front_curvature_vertical,
        double front_curvature_horizontal,
        double back_curvature_vertical,
        double back_curvature_horizontal,
        object parent=None, 
        AffineMatrix3D transform=None, 
        Material material=None, 
        str name=None,
    ):
        """Initialize a new toric bi-concave lens.

        Parameters
        ----------
        diameter : float
            The diameter of the lens frame.
        center_thickness : float
            The thickness of the lens along the lens axis.
        front_curvature_vertical : float
            Curvature radius of the front face in the Y-Z plane.
        front_curvature_horizontal : float
            Curvature radius of the front face in the X-Y plane.
        back_curvature_vertical : float
            Curvature radius of the back face in the Y-Z plane.
        back_curvature_horizontal : float
            Curvature radius of the back face in the X-Y plane.
        parent : object
            Assigns the Node's parent to the specified scene-graph object.
        transform : AffineMatrix3D
            Sets the affine transform associated with the primitive.
        material : Material
            An object representing the material properties of the primitive.
        name : str
            A string defining the primitive's name.

        Raises
        ------
        ValueError
            If vertical curvature == horizontal curvature for any of the lens faces.
        """
        self.diameter = diameter
        self.center_thickness = center_thickness
        self.front_curvature_vertical = front_curvature_vertical
        self.front_curvature_horizontal = front_curvature_horizontal
        self.back_curvature_vertical = back_curvature_vertical
        self.back_curvature_horizontal = back_curvature_horizontal

        _check_lens_parameters(self)
        self._calculate_geometry()

        front_face = Toric(
            self.front_radius_major,
            self.front_radius_minor,
            self.front_radius_minor,
            transform = (
                rotate_z(self.front_rotation_angle)
                * translate(0, 0, self.center_thickness + self.front_radius_minor)
                * ROTATE_Y180
            ),
        )

        back_face = Toric(
            self.back_radius_major,
            self.back_radius_minor,
            self.back_radius_minor,
            transform = (
                rotate_z(self.back_rotation_angle)
                * translate(0, 0, -self.back_radius_minor)
            ),
        )

        cdef double radius = 0.5 * self.diameter

        barrel = Cylinder(
            radius,
            self.edge_thickness,
            transform=translate(0, 0, -self.back_thickness),
        )

        lens = Subtract(Subtract(barrel, front_face), back_face)

        super().__init__(lens, parent, transform, material, name)

    cdef void _calculate_geometry(self):
        """Calculate geometry for both faces."""
        _calculate_toric_geometry(
            self.diameter,
            self.front_curvature_vertical,
            self.front_curvature_horizontal,
            &self.front_radius_major,
            &self.front_radius_minor,
            &self.front_thickness,
            &self.front_rotation_angle,
        )

        _calculate_toric_geometry(
            self.diameter,
            self.back_curvature_vertical,
            self.back_curvature_horizontal,
            &self.back_radius_major,
            &self.back_radius_minor,
            &self.back_thickness,
            &self.back_rotation_angle,
        )

        self.edge_thickness = self.center_thickness + self.back_thickness + self.front_thickness

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return ToricBiConcave(
            self.diameter,
            self.center_thickness,
            self.front_curvature_vertical,
            self.front_curvature_horizontal,
            self.back_curvature_vertical,
            self.back_curvature_horizontal,
            parent,
            transform,
            material,
            name
        )


cdef class ToricMeniscus(EncapsulatedPrimitive):
    """A meniscus toric lens primitive.

    A lens consisting of a concave and a convex toric surfaces aligned on a
    common axis. The two surfaces sit at either end of a cylindrical barrel
    that is aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is concave, it is the negative surface most on the z-axis. The
    front surface is convex, it is the positive most surface on the z-axis. The
    centre of the back surface lies on z=0 and with the lens extending along
    the +ve z direction.

    Attributes
    ----------
    diameter : double
        The diameter of the lens frame.
    center_thickness : double
        The thickness of the lens along the lens axis.
    front_curvature_vertical : double
        Curvature radius of the front face in the Y-Z plane.
    front_curvature_horizontal : double
        Curvature radius of the front face in the X-Y plane.
    back_curvature_vertical : double
        Curvature radius of the back face in the Y-Z plane.
    back_curvature_horizontal : double
        Curvature radius of the back face in the X-Y plane.
    parent : object
        Assigns the Node's parent to the specified scene-graph object.
    transform : AffineMatrix3D
        Sets the affine transform associated with the primitive.
    material : Material
        An object representing the material properties of the primitive.
    name : str
        A string defining the primitive's name.
    """
    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double back_curvature_vertical
        readonly double back_curvature_horizontal
        readonly double front_curvature_vertical
        readonly double front_curvature_horizontal
        readonly double back_radius_major
        readonly double back_radius_minor
        readonly double front_radius_major
        readonly double front_radius_minor
        readonly double back_thickness
        readonly double front_thickness
        readonly double back_rotation_angle
        readonly double front_rotation_angle
        readonly double edge_thickness

    def __init__(
        self, 
        double diameter,
        double center_thickness,
        double front_curvature_vertical,
        double front_curvature_horizontal,
        double back_curvature_vertical,
        double back_curvature_horizontal,
        object parent=None, 
        AffineMatrix3D transform=None, 
        Material material=None, 
        str name=None,
    ):
        """Initialize a new toric meniscus lens.

        Parameters
        ----------
        diameter : float
            The diameter of the lens frame.
        center_thickness : float
            The thickness of the lens along the lens axis.
        front_curvature_vertical : float
            Curvature radius of the front face in the Y-Z plane.
        front_curvature_horizontal : float
            Curvature radius of the front face in the X-Y plane.
        back_curvature_vertical : float
            Curvature radius of the back face in the Y-Z plane.
        back_curvature_horizontal : float
            Curvature radius of the back face in the X-Y plane.
        parent : object
            Assigns the Node's parent to the specified scene-graph object.
        transform : AffineMatrix3D
            Sets the affine transform associated with the primitive.
        material : Material
            An object representing the material properties of the primitive.
        name : str
            A string defining the primitive's name.

        Raises
        ------
        ValueError
            If vertical curvature == horizontal curvature for any of the lens faces.
        """
        self.diameter = diameter
        self.center_thickness = center_thickness
        self.front_curvature_vertical = front_curvature_vertical
        self.front_curvature_horizontal = front_curvature_horizontal
        self.back_curvature_vertical = back_curvature_vertical
        self.back_curvature_horizontal = back_curvature_horizontal

        _check_lens_parameters(self)
        self._calculate_geometry()

        if self.is_short():
            lens = self._build_short_lens()
        else:
            lens = self._build_long_lens()

        super().__init__(lens, parent, transform, material, name)

    cdef bint is_short(self):

        return self.front_radius_minor >= self.back_thickness + self.center_thickness

    cdef Primitive _build_short_lens(self):

        cdef:
            double radius = 0.5 * self.diameter
            double padding = self.edge_thickness * PADDING

        front = Toric(
            self.front_radius_major,
            self.front_radius_minor,
            self.front_radius_minor,
            transform=rotate_z(self.front_rotation_angle) * translate(0, 0, -self.front_radius_minor + self.center_thickness),
        )

        back = Toric(
            self.back_radius_major,
            self.back_radius_minor,
            self.back_radius_minor,
            transform=rotate_z(self.back_rotation_angle) * translate(0, 0, -self.back_radius_minor),
        )

        barrel = Cylinder(
            radius,
            self.back_thickness + self.center_thickness + padding,
            transform=translate(0, 0, -self.back_thickness),
        )

        return Subtract(Intersect(front, barrel), back)

    cdef Primitive _build_long_lens(self):

        cdef:
            double radius = 0.5 * self.diameter
            double padding = self.edge_thickness * PADDING

        front_face = Toric(
            self.front_radius_major,
            self.front_radius_minor,
            self.front_radius_minor,
            transform=rotate_z(self.front_rotation_angle) * translate(0, 0, -self.front_radius_minor + self.center_thickness),
        )

        front_barrel = Cylinder(
            radius,
            self.front_thickness + 2 * padding,
            transform=translate(0, 0, self.center_thickness - self.front_thickness - padding),
        )

        front_element = Intersect(front_barrel, front_face)

        back_element = Toric(
            self.back_radius_major,
            self.back_radius_minor,
            self.back_radius_minor,
            transform=rotate_z(self.back_rotation_angle) * translate(0, 0, -self.back_radius_minor),
        )

        barrel = Cylinder(
            radius,
            self.edge_thickness + padding,
            transform=translate(0, 0, -self.back_thickness),
        )

        return Subtract(Union(barrel, front_element), back_element)

    cdef void _calculate_geometry(self):
        """Calculate geometry for both faces."""
        _calculate_toric_geometry(
            self.diameter,
            self.front_curvature_vertical,
            self.front_curvature_horizontal,
            &self.front_radius_major,
            &self.front_radius_minor,
            &self.front_thickness,
            &self.front_rotation_angle,
        )

        _calculate_toric_geometry(
            self.diameter,
            self.back_curvature_vertical,
            self.back_curvature_horizontal,
            &self.back_radius_major,
            &self.back_radius_minor,
            &self.back_thickness,
            &self.back_rotation_angle,
        )

        self.edge_thickness = self.center_thickness + self.back_thickness - self.front_thickness

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return ToricMeniscus(
            self.diameter,
            self.center_thickness,
            self.front_curvature_vertical,
            self.front_curvature_horizontal,
            self.back_curvature_vertical,
            self.back_curvature_horizontal,
            parent,
            transform,
            material,
            name
        )


cdef class ToricPlanoConvex(EncapsulatedPrimitive):
    """A plano-convex toric lens primitive.

    A lens consisting of a convex toric surface and a plane (flat) surface,
    aligned on a common axis. The two surfaces sit at either end of a
    cylindrical barrel that is aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the plane surface, it is the negative surface most on the
    z-axis. The front surface is the spherical surface, it is the positive most
    surface on the z-axis. The back (plane) surface lies on z=0 with the lens
    extending along the +ve z direction.

    Attributes
    ----------
    diameter : double
        The diameter of the lens frame.
    center_thickness : double
        The thickness of the lens along the lens axis.
    curvature_vertical : double
        Curvature radius of the front face in the Y-Z plane.
    curvature_horizontal : double
        Curvature radius of the front face in the X-Y plane.
    parent : object
        Assigns the Node's parent to the specified scene-graph object.
    transform : AffineMatrix3D
        Sets the affine transform associated with the primitive.
    material : Material
        An object representing the material properties of the primitive.
    name : str
        A string defining the primitive's name.
    """
    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double curvature_vertical
        readonly double curvature_horizontal
        readonly double radius_major
        readonly double radius_minor
        readonly double curve_thickness
        readonly double rotation_angle
        readonly double edge_thickness

    def __init__(
        self, 
        double diameter,
        double center_thickness,
        double curvature_vertical,
        double curvature_horizontal,
        object parent=None, 
        AffineMatrix3D transform=None, 
        Material material=None, 
        str name=None,
    ):
        """Initialize a new plano-convex toric lens.

        Attributes
        ----------
        diameter : double
            The diameter of the lens frame.
        center_thickness : double
            The thickness of the lens along the lens axis.
        curvature_vertical : double
            Curvature radius of the front face in the Y-Z plane.
        curvature_horizontal : double
            Curvature radius of the front face in the X-Y plane.
        parent : object
            Assigns the Node's parent to the specified scene-graph object.
        transform : AffineMatrix3D
            Sets the affine transform associated with the primitive.
        material : Material
            An object representing the material properties of the primitive.
        name : str
            A string defining the primitive's name.
        """
        cdef double radius = 0.5 * diameter

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.curvature_vertical = curvature_vertical
        self.curvature_horizontal = curvature_horizontal

        if self.diameter <= 0:
            raise ValueError(f"lens diameter must be positive, got {self.diameter}")

        if self.center_thickness <= 0:
            raise ValueError(f"lens center thickness must be positive, got {self.center_thickness}")

        if self.curvature_vertical <= 0:
            raise ValueError(f"lens vertical curvature radius must be positive, got {self.curvature_vertical}")

        if self.curvature_vertical < radius:
            raise ValueError(f"lens vertical curvature radius must be greater than barrel radius, got {self.curvature_vertical} < {radius}")

        if self.curvature_horizontal <= 0:
            raise ValueError(f"lens horizontal curvature radius must be positive, got {self.curvature_horizontal}")

        if self.curvature_horizontal < radius:
            raise ValueError(f"lens horizontal curvature radius must be greater than barrel radius, got {self.curvature_horizontal} < {radius}")

        self._calculate_geometry()

        if self.is_short():
            lens = self._build_short_lens()
        else:
            lens = self._build_long_lens()

        super().__init__(lens, parent, transform, material, name)

    cdef void _calculate_geometry(self) except *:

        _calculate_toric_geometry(
            self.diameter,
            self.curvature_vertical,
            self.curvature_horizontal,
            &self.radius_major,
            &self.radius_minor,
            &self.curve_thickness,
            &self.rotation_angle,
        )

        self.edge_thickness = self.center_thickness - self.curve_thickness

    cdef bint is_short(self):

        return self.radius_minor - self.curve_thickness > self.edge_thickness

    cdef Primitive _build_short_lens(self):

        cdef:
            double radius = 0.5 * self.diameter
            double padding = self.center_thickness * PADDING

        front = Toric(
            self.radius_major,
            self.radius_minor,
            self.radius_minor,
            transform=rotate_z(self.rotation_angle) * translate(0, 0, -self.radius_minor + self.center_thickness),
        )

        barrel = Cylinder(
            radius,
            self.center_thickness + padding,
        )

        return Intersect(front, barrel)

    cdef Primitive _build_long_lens(self):

        cdef:
            double radius = 0.5 * self.diameter
            double padding = self.center_thickness * PADDING

        front_face = Toric(
            self.radius_major,
            self.radius_minor,
            self.radius_minor,
            transform=rotate_z(self.rotation_angle) * translate(0, 0, -self.radius_minor + self.center_thickness),
        )

        front_barrel = Cylinder(
            radius,
            self.curve_thickness + 2 * padding,
            transform=translate(0, 0, self.edge_thickness - padding),
        )

        front_element = Intersect(front_face, front_barrel)

        barrel = Cylinder(
            radius,
            self.edge_thickness,
        )

        return Union(front_element, barrel)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return ToricPlanoConvex(self.diameter, self.center_thickness, self.curvature_vertical, self.curvature_horizontal, parent, transform, material, name)


cdef class ToricPlanoConcave(EncapsulatedPrimitive):
    """A plano-concave toric lens primitive.

    A lens consisting of a concave toric surface and a plane (flat)
    surface, aligned on a common axis. The two surfaces sit at either end of a
    cylindrical barrel that is aligned to lie along the z-axis.

    The two lens surfaces are referred to as front and back respectively. The
    back surface is the plane surface, it is the negative surface most on the
    z-axis. The front surface is the spherical surface, it is the positive most
    surface on the z-axis. The back (plane) surface lies on z=0 with the lens
    extending along the +ve z direction.

    Attributes
    ----------
    diameter : double
        The diameter of the lens frame.
    center_thickness : double
        The thickness of the lens along the lens axis.
    curvature_vertical : double
        Curvature radius of the front face in the Y-Z plane.
    curvature_horizontal : double
        Curvature radius of the front face in the X-Y plane.
    parent : object
        Assigns the Node's parent to the specified scene-graph object.
    transform : AffineMatrix3D
        Sets the affine transform associated with the primitive.
    material : Material
        An object representing the material properties of the primitive.
    name : str
        A string defining the primitive's name.
    """
    cdef:
        readonly double diameter
        readonly double center_thickness
        readonly double curvature_vertical
        readonly double curvature_horizontal
        readonly double radius_major
        readonly double radius_minor
        readonly double curve_thickness
        readonly double rotation_angle
        readonly double edge_thickness

    def __init__(
        self, 
        double diameter,
        double center_thickness,
        double curvature_vertical,
        double curvature_horizontal,
        object parent=None, 
        AffineMatrix3D transform=None, 
        Material material=None, 
        str name=None,
    ):
        """Initialize a new plano-concave toric lens.

        Attributes
        ----------
        diameter : double
            The diameter of the lens frame.
        center_thickness : double
            The thickness of the lens along the lens axis.
        curvature_vertical : double
            Curvature radius of the front face in the Y-Z plane.
        curvature_horizontal : double
            Curvature radius of the front face in the X-Y plane.
        parent : object
            Assigns the Node's parent to the specified scene-graph object.
        transform : AffineMatrix3D
            Sets the affine transform associated with the primitive.
        material : Material
            An object representing the material properties of the primitive.
        name : str
            A string defining the primitive's name.
        """
        cdef double radius = 0.5 * diameter

        self.diameter = diameter
        self.center_thickness = center_thickness
        self.curvature_vertical = curvature_vertical
        self.curvature_horizontal = curvature_horizontal

        if self.diameter <= 0:
            raise ValueError(f"lens diameter must be positive, got {self.diameter}")

        if self.center_thickness <= 0:
            raise ValueError(f"lens center thickness must be positive, got {self.center_thickness}")

        if self.curvature_vertical <= 0:
            raise ValueError(f"lens vertical curvature radius must be positive, got {self.curvature_vertical}")

        if self.curvature_vertical < radius:
            raise ValueError(f"lens vertical curvature radius must be greater than barrel radius, got {self.curvature_vertical} < {radius}")

        if self.curvature_horizontal <= 0:
            raise ValueError(f"lens horizontal curvature radius must be positive, got {self.curvature_horizontal}")

        if self.curvature_horizontal < radius:
            raise ValueError(f"lens horizontal curvature radius must be greater than barrel radius, got {self.curvature_horizontal} < {radius}")

        self._calculate_geometry()

        front = Toric(
            self.radius_major,
            self.radius_minor,
            self.radius_minor,
            transform = (
                rotate_z(self.rotation_angle)
                * translate(0, 0, self.center_thickness + self.radius_minor)
                * ROTATE_Y180
            ),
        )

        barrel = Cylinder(
            radius,
            self.edge_thickness,
        )

        lens = Subtract(barrel, front)

        super().__init__(lens, parent, transform, material, name)

    cdef void _calculate_geometry(self) except *:

        _calculate_toric_geometry(
            self.diameter,
            self.curvature_vertical,
            self.curvature_horizontal,
            &self.radius_major,
            &self.radius_minor,
            &self.curve_thickness,
            &self.rotation_angle,
        )

        self.edge_thickness = self.center_thickness + self.curve_thickness

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return ToricPlanoConcave(self.diameter, self.center_thickness, self.curvature_vertical, self.curvature_horizontal, parent, transform, material, name)
