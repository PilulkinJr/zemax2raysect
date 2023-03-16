# cython: language_level=3

cimport cython

from raysect.core cimport new_point3d, Point3D, new_normal3d, AffineMatrix3D, Material, new_intersection, BoundingBox3D
from raysect.core.math.cython cimport swap_double, swap_int
from libc.math cimport sqrt, isnan, fabs
from libc.complex cimport cimag, creal

from ..utility cimport solve_quartic

import numpy as np
cimport numpy as np

np.import_array()

# cython doesn't have a built-in infinity constant, this compiles to +infinity
DEF INFINITY = 1e999

# bounding box is padded by a small amount to avoid numerical accuracy issues
DEF BOX_PADDING = 1e-9

# TODO - Perhaps should be calculated based on primitive scale
# additional ray distance to avoid re-hitting the same surface point
DEF EPSILON = 1e-9

cdef bint _pick_roots(
    double complex z0,
    double complex z1,
    double complex z2,
    double complex z3,
    double *t0,
    double *t1,
):
    """Pick appropriate roots of the quartic equation.

    Picks smallest and largest real roots.
    Returns True if these two roots are present, False -- otherwise.

    :param double comlex z0, z1, z2, z3: Roots of the quartic equation.
    :param double* t0, t1: Picked roots.
    """
    cdef:
        list result = []
        double complex z
        double re, im
    
    for z in (z0, z1, z2, z3):
        # if abs(cimag(z)) < 1.0e-15 and not isnan(creal(z)):
        re = creal(z)
        im = cimag(z)
        if not isnan(re) and fabs(im) < 1e-6 * fabs(re):
            result.append(re)
            
    if len(result) < 2:
        return False
    
    result = list(sorted(result))

    t0[0] = result[0]
    t1[0] = result[-1]
    
    return True


cdef class TorusSegment(Primitive):
    """Torus segment primitive.

    The segment of a torus is defined by torus major radius, minor radius and height of the segment.

    :param float radius_major: Major radius of the torus in meters (default = 2.0).
    :param float radius_minor: Minor radius of the torus in meters (default = 1.0).
    :param float height: Height of the segment in meters (default = 0.5).
    :param Node parent: Scene-graph parent node or None (default = None).
    :param AffineMatrix3D transform: An AffineMatrix3D defining the local co-ordinate system relative to the scene-graph parent (default = identity matrix).
    :param Material material: A Material object defining the parabola's material (default = None).
    :param str name: A string specifying a user-friendly name for the parabola (default = "").
    """

    def __init__(
        self,
        double radius_major=2.0,
        double radius_minor=1.0,
        double height=1.0,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name="",
    ):

        # Cannot handle the sphere case -- major radius = 0.
        if radius_major < 0.0:
            raise ValueError("Torus' major radius must be positive.")

        if radius_minor < 0.0:
            raise ValueError("Torus' minor radius must be positive.")

        if height <= 0.0:
            raise ValueError("Torus' height cannot be less than zero.")

        if radius_minor < height:
            raise ValueError("Torus' minor radius has to be greater than or equal to height.")

        super().__init__(parent, transform, material, name)

        self._radius_major = radius_major
        self._radius_minor = radius_minor
        self._height = height
        self._shift = -radius_major - radius_minor

        # initialise next intersection caching and control attributes
        self._further_intersection = False
        self._next_t = 0.0
        self._cached_origin = None
        self._cached_direction = None
        self._cached_ray = None

    @property
    def radius_major(self):
        """
        Radius of the torus in x-y plane.
        """
        return self._radius_major

    @radius_major.setter
    def radius_major(self, double value):
        if value <= 0.0:
            raise ValueError("Torus horizontal radius cannot be less than or equal to zero.")
        self._radius_major = value
        self._shift = -value - self._radius_minor

        # the next intersection cache has been invalidated by the geometry change
        self._further_intersection = False

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    @property
    def radius_minor(self):
        """
        Radius of the torus in the y-z plane
        """
        return self._radius_minor

    @radius_minor.setter
    def radius_minor(self, double value):
        if value <= 0.0:
            raise ValueError("Torus vertical radius cannot be less than or equal to zero.")
        if value < self._height:
            raise ValueError("Torus' minor radius has to be greater than height.")
        self._radius_minor = value
        self._shift = -self._radius_major - value

        # the next intersection cache has been invalidated by the geometry change
        self._further_intersection = False

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    @property
    def height(self):
        """
        The torus segment's extent along the z-axis [0, height].
        """
        return self._height

    @height.setter
    def height(self, double value):
        if value <= 0.0:
            raise ValueError("Torus height cannot be less than or equal to zero.")
        if self._radius_minor < value:
            raise ValueError("Torus' minor radius has to be greater than height.")
        if self._radius_minor < value:
            raise ValueError("Vertical radius is not allowed to be less than height.")

        self._height = value

        # the next intersection cache has been invalidated by the geometry change
        self._further_intersection = False

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    @cython.cdivision(True)
    cpdef Intersection hit(self, Ray ray):

        cdef:
            Point3D origin
            Vector3D direction
            double radius_minor, radius_major, height, shift
            double alpha, beta, gamma, delta, sigma
            double o2x, o2y, o2z
            double d2x, d2y, d2z
            double r2maj, r2min, xi, ix
            double a, b, c, d, e
            double complex z0, z1, z2, z3
            double t0, t1, t0_z, t1_z
            int t0_type, t1_type
            bint t0_outside, t1_outside
            double closest_intersection
            int closest_type

        # reset the next intersection cache
        self._further_intersection = False

        # convert ray origin and direction to local space
        origin = ray.origin.transform(self.to_local())
        direction = ray.direction.transform(self.to_local())

        o2x = origin.x * origin.x
        o2y = origin.y * origin.y
        o2z = (origin.z + self._shift) * (origin.z + self._shift)

        d2x = direction.x * direction.x
        d2y = direction.y * direction.y
        d2z = direction.z * direction.z

        r2maj = self._radius_major * self._radius_major
        r2min = self._radius_minor * self._radius_minor
        xi = r2maj - r2min
        ix = r2maj + r2min

        alpha = d2x + d2y + d2z
        beta = origin.x * direction.x + origin.y * direction.y + (origin.z + self._shift) * direction.z
        gamma = o2x + o2y + o2z
        delta = gamma + xi
        sigma = gamma - ix

        a = alpha * alpha
        b = 4.0 * alpha * beta
        c = 2.0 * alpha * delta - 4.0 * r2maj * (d2x + d2z) + 4.0 * beta * beta
        d = 8.0 * r2maj * origin.y * direction.y + 4.0 * beta * sigma
        e = gamma * gamma + xi * xi - 2.0 * ((o2x + o2z) * ix - o2y * xi)

        solve_quartic(a, b, c, d, e, &z0, &z1, &z2, &z3)

        if not _pick_roots(z0, z1, z2, z3, &t0, &t1):
            return None

        t0_z = origin.z + t0 * direction.z
        t1_z = origin.z + t1 * direction.z

        t0_outside = t0_z < 0 or t0_z > self._height
        t1_outside = t1_z < 0 or t1_z > self._height

        # ensure t0 is always smaller (closer) than t1
        if t0 > t1:
            swap_double(&t0, &t1)

        # are there any intersections inside the ray search range?
        if t0 > ray.max_distance or t1 < 0.0:
            return None

        # identify closest intersection
        if t0 >= 0.0 and not t0_outside:
            closest_intersection = t0

            # If there is a further intersection, setup values for next calculation.
            if t1 <= ray.max_distance and not t1_outside:
                self._further_intersection = True
                self._next_t = t1
                self._cached_origin = origin
                self._cached_direction = direction
                self._cached_ray = ray

        elif t1 <= ray.max_distance and not t1_outside:
            closest_intersection = t1

        else:
            return None

        return self._generate_intersection(ray, origin, direction, closest_intersection)

    cpdef Intersection next_intersection(self):

        if not self._further_intersection:
            return None

        # this is the 2nd and therefore last intersection
        self._further_intersection = False

        return self._generate_intersection(self._cached_ray, self._cached_origin, self._cached_direction, self._next_t)

    @cython.cdivision(True)
    cdef Intersection _generate_intersection(self, Ray ray, Point3D origin, Vector3D direction, double ray_distance):

        cdef:
            Point3D hit_point, inside_point, outside_point
            Normal3D normal
            bint exiting
            double k

        # point of surface intersection in local space
        hit_point = new_point3d(
            origin.x + ray_distance * direction.x,
            origin.y + ray_distance * direction.y,
            origin.z + ray_distance * direction.z
        )

        k = 1.0 - self._radius_major / sqrt(hit_point.x * hit_point.x + (hit_point.z + self._shift) * (hit_point.z + self._shift))
        normal = new_normal3d(k * hit_point.x, hit_point.y, k * (hit_point.z + self._shift))
        normal = normal.normalise()

        if direction.dot(normal) > 0:
            normal = -normal

        # displace hit_point away from surface to generate inner and outer points
        # inside_point = self._interior_point(hit_point, normal, type)

        inside_point = new_point3d(
            hit_point.x - EPSILON * normal.x,
            hit_point.y - EPSILON * normal.y,
            hit_point.z - EPSILON * normal.z
        )

        outside_point = new_point3d(
            hit_point.x + EPSILON * normal.x,
            hit_point.y + EPSILON * normal.y,
            hit_point.z + EPSILON * normal.z
        )

        # is ray exiting surface
        exiting = direction.dot(normal) >= 0.0

        return new_intersection(ray, ray_distance, self, hit_point, inside_point, outside_point,
                                normal, exiting, self.to_local(), self.to_root())

    @cython.cdivision(True)
    cpdef bint contains(self, Point3D point) except -1:

        cdef:
            double x, y, z
            double left, right

        # convert point to local object space
        point = point.transform(self.to_local())
        z = point.z

        # reject points that are outside the torus' height range
        if z < 0 or z > self._height:
            return False

        x = point.x
        y = point.y
        z += self._shift

        left = x*x + y*y + z*z
        left -= self._radius_major * self._radius_major + self._radius_minor * self._radius_minor
        left *= left

        right = 4 * self._radius_major * self._radius_major * (x*x + z*z)

        return left == right

    cpdef BoundingBox3D bounding_box(self):

        cdef:
            list points
            Point3D point
            BoundingBox3D box
            double a, b
            double semi_height_y, semi_height_x

        box = BoundingBox3D()

        # calculate local bounds
        a = self._radius_minor
        b = a - self._height
        semi_height_y = sqrt(a * a - b * b)

        a = self._radius_major + self._radius_minor
        b = a - self._height
        semi_height_x = sqrt(a * a - b * b)

        box.lower = new_point3d(-semi_height_x, -semi_height_y, 0.0)
        box.upper = new_point3d(semi_height_x, semi_height_y, self._height)

        # obtain local space vertices
        points = box.vertices()

        # convert points to world space and build an enclosing world space bounding box
        # a small degree of padding is added to avoid potential numerical accuracy issues
        box = BoundingBox3D()
        for point in points:
            box.extend(point.transform(self.to_root()), BOX_PADDING)

        return box

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return TorusSegment(self._radius_major, self._radius_minor, self._height, parent, transform, material, name)
