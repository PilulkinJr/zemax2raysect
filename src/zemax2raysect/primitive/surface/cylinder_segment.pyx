from libc.math cimport sqrt

from raysect.core cimport (
    Material,
    new_intersection,
    BoundingBox3D,
    BoundingSphere3D,
    new_point3d,
    new_normal3d,
    Normal3D,
    AffineMatrix3D
)
from raysect.core.math.cython cimport solve_quadratic, swap_double

DEF EPSILON = 1e-9
DEF BOX_PADDING = 1e-9

cdef class CylinderSegment(Primitive):

    def __init__(
        self,
        double width,
        double curvature,
        double curve_thickness,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):
        if width <= 0:
            raise ValueError("Cylinder segment width must be positive.")

        if curvature <= 0:
            raise ValueError("Cylinder segment curvature must be positive.")

        if curve_thickness > curvature:
            raise ValueError("Cylinder segment curve thickness must be less than its curvature.")

        self._width = width
        self._curvature = curvature
        self._curve_thickness = curve_thickness
        self._height = sqrt(self._curve_thickness * (2 * self._curvature - self._curve_thickness))

        super().__init__(parent, transform, material, name)

        # initialise next intersection caching and control attributes
        self._further_intersection = False
        self._next_t = 0.0
        self._cached_origin = None
        self._cached_direction = None
        self._cached_ray = None

    @property
    def width(self):
        return self._width

    @width.setter
    def width(self, value):

        if value == self._width:
            return

        if value <= 0:
            raise ValueError("Cylinder segment width must be positive.")

        self._width = value

        self._further_intersection = False
        self.notify_geometry_change()

    @property
    def curvature(self):
        return self._curvature

    @curvature.setter
    def curvature(self, value):

        if value == self._curvature:
            return

        if value <= 0:
            raise ValueError("Cylinder segment curvature must be positive.")

        if value < self._curve_thickness:
            raise ValueError("Cylinder segment curvature must be greater than its curve thickness.")

        self._curvature = value

        self._further_intersection = False
        self.notify_geometry_change()

    @property
    def curve_thickness(self):
        return self._curve_thickness

    @curve_thickness.setter
    def curve_thickness(self, value):

        if value == self._curve_thickness:
            return

        if value <= 0:
            raise ValueError("Cylinder segment curve thickness must be positive.")

        if value > self._curvature:
            raise ValueError("Cylinder segment curvature must be greater than its curve thickness.")

        self._curve_thickness = value

        self._further_intersection = False
        self.notify_geometry_change()

    @property
    def height(self):
        return self._height

    cpdef Intersection hit(self, Ray ray):

        cdef Point3D origin
        cdef Vector3D direction
        cdef double a, b, c, t0, t1, t_closest
        cdef double t0_x, t1_x, t0_z, t1_z
        cdef bint t0_outside, t1_outside

        # reset further intersection state
        self._further_intersection = False

        # convert ray parameters to local space
        origin = ray.origin.transform(self.to_local())
        direction = ray.direction.transform(self.to_local())

        a = direction.y * direction.y + direction.z * direction.z
        b = 2 * (origin.y * direction.y + direction.z * (origin.z - self._curvature))
        c = origin.y * origin.y + origin.z * origin.z - 2 * origin.z * self._curvature

        if not solve_quadratic(a, b, c, &t0, &t1):
            return None

        if t0 > t1:
            swap_double(&t0, &t1)

        t0_x = origin.x + t0 * direction.x
        t1_x = origin.x + t1 * direction.x

        t0_z = origin.z + t0 * direction.z
        t1_z = origin.z + t1 * direction.z

        t0_outside = t0_z < 0 or t0_z > self._curve_thickness or t0_x < -0.5 * self._width or t0_x > 0.5 * self._width
        t1_outside = t1_z < 0 or t1_z > self._curve_thickness or t1_x < -0.5 * self._width or t1_x > 0.5 * self._width

        # print(t0, t0_z, t0_x, t0_outside)
        # print(t1, t1_z, t1_x, t1_outside)
        # print()

        if t0_outside and t1_outside:
            return None

        # test the intersection points inside the ray search range [0, max_distance]
        if t0 > ray.max_distance or t1 < 0.0:
            return None

        if t0 >= 0.0 and not t0_outside:
            t_closest = t0
            # if t1 <= ray.max_distance and not t1_outside:
            #     self._further_intersection = True
            #     self._cached_ray = ray
            #     self._cached_origin = origin
            #     self._cached_direction = direction
            #     self._next_t = t1
        elif t1 <= ray.max_distance and not t1_outside:
            t_closest = t1
        else:
            return None

        return self._generate_intersection(ray, origin, direction, t_closest)

    cpdef Intersection next_intersection(self):

        if not self._further_intersection:
            return None

        # this is the 2nd and therefore last intersection
        self._further_intersection = False

        return self._generate_intersection(self._cached_ray, self._cached_origin, self._cached_direction, self._next_t)

    cdef Intersection _generate_intersection(self, Ray ray, Point3D origin, Vector3D direction, double ray_distance):

        cdef Point3D hit_point, inside_point, outside_point
        cdef Normal3D normal
        cdef double delta_x, delta_y, delta_z
        cdef bint exiting

        # point of surface intersection in local space
        hit_point = new_point3d(
            origin.x + ray_distance * direction.x,
            origin.y + ray_distance * direction.y,
            origin.z + ray_distance * direction.z
        )

        # normal is normalised vector from sphere origin to hit_point
        normal = new_normal3d(0, hit_point.y, hit_point.z - self._curvature)
        normal = normal.normalise()

        if direction.dot(normal) > 0:
            normal = -normal

        # calculate points inside and outside of surface for daughter rays to
        # spawn from - these points are displaced from the surface to avoid
        # re-hitting the same surface
        delta_y = EPSILON * normal.y
        delta_z = EPSILON * normal.z

        inside_point = new_point3d(hit_point.x, hit_point.y - delta_y, hit_point.z - delta_z)
        outside_point = new_point3d(hit_point.x, hit_point.y + delta_y, hit_point.z + delta_z)

        # is ray exiting surface
        exiting = direction.dot(normal) >= 0.0

        return new_intersection(
            ray,
            ray_distance,
            self,
            hit_point,
            inside_point,
            outside_point,
            normal,
            exiting,
            self.to_local(),
            self.to_root(),
        )

    cpdef bint contains(self, Point3D point) except -1:

        cdef Point3D local_point
        cdef double x, y, z
        cdef double distance_sqr

        # convert world space point to local space
        local_point = point.transform(self.to_local())
        x = local_point.x
        y = local_point.y
        z = local_point.z

        if z < 0 or z > self._curve_thickness:
            return False

        if x < -0.5 * self._width or x > 0.5 * self._width:
            return False

        distance_sqr = y * y + (z - self._curvature) * (z - self._curvature)

        return distance_sqr <= self._curvature * self._curvature

    cpdef BoundingBox3D bounding_box(self):

        cdef:
            double y_width
            BoundingBox3D box
            list points
            Point3D point

        box = BoundingBox3D()
        box.lower = new_point3d(-0.5 * self._width, -0.5 * self._height, 0)
        box.upper = new_point3d(0.5 * self._width, 0.5 * self._height, self._curve_thickness)

        points = box.vertices()

        box = BoundingBox3D()
        for point in points:
            box.extend(point.transform(self.to_root()), BOX_PADDING)

        return box

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return CylinderSegment(self._width, self._curvature, self._curve_thickness, parent, transform, material, name)
