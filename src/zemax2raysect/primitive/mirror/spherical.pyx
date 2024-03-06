from libc.math cimport sqrt, fmax, fmin

from raysect.core cimport AffineMatrix3D, Material, translate, Point3D
from raysect.primitive import Intersect, Subtract, Sphere, Cylinder, Box
from raysect.primitive.utility cimport EncapsulatedPrimitive


DEF PADDING = 0.000001


cdef class RoundSphericalMirror(EncapsulatedPrimitive):
    """
    Primitive for a round spherical mirror with an aperture.

    A thin mirror is formed by two spherical surfaces, in a way that both curvature center lie in +z direction.
    Center of the front surface lies at z=0, independent on the center of the mirror's frame in XY plane.
    Center of the back surface lies in -z direction.

    :param float diameter: Diameter of the mirror's frame in [m].
    :param float curvature: Radius of curvature in meters in [m].
    :param float aperture: Diameter of the mirror aperture (cutout) in [m], concentric with the frame (default = 0).
    :param float horizontal_decenter: Decenter of the mirror's frame and aperture along x direction in [m] (default = 0).
    :param float vertical_decenter: Decenter of the mirror's frame and aperture along y direction in [m] (default = 0).
    :param Node parent: Assigns the primitive's parent to the specified scene-graph object (default = None).
    :param AffineMatrix3D transform: Sets the affine transform associated with the primitive (default = None).
    :param Material material: An object representing the material properties of the primitive (default = None).
    :param str name: A string defining the mirror's name (default = None).
    """
    cdef:
        readonly double diameter
        readonly double curvature
        readonly double curve_thickness
        readonly double aperture
        readonly double horizontal_decenter
        readonly double vertical_decenter
        readonly double center_thickness

    def __init__(
        self,
        double diameter,
        double curvature,
        double aperture=0,
        double horizontal_decenter=0,
        double vertical_decenter=0,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):
        if diameter <= 0:
            raise ValueError(f"Spherical mirror's diameter cannot be less than or equal to zero, got {diameter}")

        if curvature <= 0:
            raise ValueError(f"Spherical mirror's curvature cannot be less than or equal to zero, got {curvature}")

        if aperture < 0:
            raise ValueError(f"Spherical mirror's aperture cannot be less than zero, got {aperture}.")

        if aperture >= diameter:
            raise ValueError(f"Spherical mirror's aperture must be smaller than the diameter of its frame, got {aperture} >= {diameter}.")

        cdef double radius = 0.5 * diameter
        cdef double decenter_r = sqrt(horizontal_decenter * horizontal_decenter + vertical_decenter * vertical_decenter)
        cdef double frame_outer_r = decenter_r + radius
        cdef double frame_inner_r = fmax(0, decenter_r - radius)

        if curvature < frame_outer_r:
            raise ValueError("Spherical mirror's curvature cannot be less than the radius of its frame "
                             f"+ |horizontal_decenter|, got {curvature} < {frame_outer_r}.")

        self.diameter = diameter
        self.curvature = curvature
        self.aperture = aperture
        self.horizontal_decenter = horizontal_decenter
        self.vertical_decenter = vertical_decenter

        cdef double frame_inner_z = curvature - sqrt(curvature * curvature - frame_inner_r * frame_inner_r)
        cdef double frame_outer_z = curvature - sqrt(curvature * curvature - frame_outer_r * frame_outer_r)

        self.curve_thickness = frame_outer_z - frame_inner_z
        self.center_thickness = self.curve_thickness * PADDING

        outer_sphere = Sphere(self.curvature + self.center_thickness)
        inner_sphere = Sphere(self.curvature)

        hollow_sphere = Subtract(outer_sphere, inner_sphere, transform=translate(0, 0, self.curvature))

        frame = Cylinder(radius, self.curve_thickness + self.center_thickness,
                         transform=translate(self.horizontal_decenter,
                                             self.vertical_decenter,
                                             frame_inner_z - self.center_thickness))

        mirror = Intersect(hollow_sphere, frame)

        if self.aperture > 0:
            transform = translate(self.horizontal_decenter, self.vertical_decenter, frame_inner_z - self.center_thickness - PADDING)
            aperture_cylinder = Cylinder(0.5 * self.aperture, self.curve_thickness + self.center_thickness + PADDING,
                                         transform=transform)

            mirror = Subtract(mirror, aperture_cylinder)

        super().__init__(mirror, parent, transform, material, name)


cdef class RectangularSphericalMirror(EncapsulatedPrimitive):
    """
    Primitive for a rectangular spherical mirror with an aperture.

    A thin mirror is formed by two spherical surfaces, in a way that both curvature center lie in +z direction.
    Center of the front surface lies at z=0, independent on the center of the mirror's frame in XY plane.
    Center of the back surface lies in -z direction.

    :param float width: width of the mirror's frame along x axis.
    :param float height: height of the mirror's frame along y axis.
    :param float curvature: Radius of curvature in meters.
    :param float aperture: Diameter of the mirror aperture (cutout) in [m], concentric with the frame (default = 0).
    :param float horizontal_decenter: Decenter of the mirror's frame and aperture along x direction in [m] (default = 0).
    :param float vertical_decenter: Decenter of the mirror's frame and aperture along y direction in [m] (default = 0).
    :param Node parent: Assigns the primitive's parent to the specified scene-graph object (default = None).
    :param AffineMatrix3D transform: Sets the affine transform associated with the primitive (default = None).
    :param Material material: An object representing the material properties of the primitive (default = None).
    :param str name: A string defining the mirror's name (default = None).
    """

    cdef:
        readonly double width
        readonly double height
        readonly double curvature
        readonly double curve_thickness
        readonly double aperture
        readonly double horizontal_decenter
        readonly double vertical_decenter
        readonly double center_thickness

    def __init__(
        self,
        double width,
        double height,
        double curvature,
        double aperture=0,
        double horizontal_decenter=0,
        double vertical_decenter=0,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):

        if width <= 0:
            raise ValueError(f"Spherical mirror's width cannot be less than or equal to zero, got {width}")

        if height <= 0:
            raise ValueError(f"Spherical mirror's height cannot be less than or equal to zero, got {height}")

        if curvature <= 0:
            raise ValueError(f"Spherical mirror's curvature radius cannot be less than or equal to zero, got {curvature}")

        if aperture < 0:
            raise ValueError(f"Spherical mirror's aperture cannot be less than zero, got {aperture}.")

        if aperture >= width:
            raise ValueError(f"Spherical mirror's aperture must be smaller than the width of its frame, got {aperture} >= {width}.")

        if aperture >= height:
            raise ValueError(f"Spherical mirror's aperture must be smaller than the height of its frame, got {aperture} >= {height}.")

        cdef double half_width = 0.5 * width
        cdef double half_height = 0.5 * height
        cdef double frame_right = horizontal_decenter + half_width
        cdef double frame_left = horizontal_decenter - half_width
        cdef double frame_top = vertical_decenter + half_height
        cdef double frame_bottom = vertical_decenter - half_height

        cdef double frame_outer_x = fmax(abs(frame_right), abs(frame_left))
        cdef double frame_outer_y = fmax(abs(frame_bottom), abs(frame_top))
        cdef double frame_outer_r = sqrt(frame_outer_x * frame_outer_x + frame_outer_y * frame_outer_y)

        if curvature < frame_outer_r:
            raise ValueError("Spherical mirror's rectangular frame does not fit into hemisphere,"
                             f" {curvature} < {frame_outer_r}.")

        self.width = width
        self.height = height
        self.curvature = curvature
        self.aperture = aperture
        self.horizontal_decenter = horizontal_decenter
        self.vertical_decenter = vertical_decenter

        cdef double frame_inner_x = 0 if frame_left < 0 < frame_right else fmin(abs(frame_right), abs(frame_left))
        cdef double frame_inner_y = 0 if frame_bottom < 0 < frame_top else fmin(abs(frame_bottom), abs(frame_top))
        cdef double frame_inner_r = sqrt(frame_inner_x * frame_inner_x + frame_inner_y * frame_inner_y)

        cdef double frame_inner_z = curvature - sqrt(curvature * curvature - frame_inner_r * frame_inner_r)
        cdef double frame_outer_z = curvature - sqrt(curvature * curvature - frame_outer_r * frame_outer_r)

        self.curve_thickness = frame_outer_z - frame_inner_z
        self.center_thickness = self.curve_thickness * PADDING

        outer_sphere = Sphere(self.curvature + self.center_thickness)
        inner_sphere = Sphere(self.curvature)

        hollow_sphere = Subtract(outer_sphere, inner_sphere, transform=translate(0, 0, self.curvature))

        print(frame_left, frame_bottom, frame_inner_z)
        print(frame_right, frame_top, frame_outer_z)

        lower = Point3D(frame_left, frame_bottom, frame_inner_z - self.center_thickness)
        upper = Point3D(frame_right, frame_top, frame_outer_z)
        frame = Box(lower, upper)

        mirror = Intersect(hollow_sphere, frame)

        if self.aperture > 0:
            transform = translate(self.horizontal_decenter, self.vertical_decenter, frame_inner_z - self.center_thickness - PADDING)
            aperture_cylinder = Cylinder(0.5 * self.aperture, self.curve_thickness + self.center_thickness + PADDING,
                                         transform=transform)

            mirror = Subtract(mirror, aperture_cylinder)

        super().__init__(mirror, parent, transform, material, name)
