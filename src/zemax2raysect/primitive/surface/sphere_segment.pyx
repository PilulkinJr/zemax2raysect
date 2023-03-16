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

# bounding box and sphere are padded by small amounts to avoid numerical accuracy issues
DEF BOX_PADDING = 1e-9
DEF SPHERE_PADDING = 1.000000001

# additional ray distance to avoid re-hitting the same surface point
DEF EPSILON = 1e-9


cdef class SphereSegment(Primitive):

    def __init__(
        self,
        double diameter=0.5,
        double curvature=0.5,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):

        super().__init__(parent, transform, material, name)

        if diameter <= 0.0:
            raise ValueError("Sphere segment barrel diameter must be positive.")

        if curvature <= 0.0:
            raise ValueError("Sphere segment curvature must be positive.")

        if 0.5 * diameter > curvature:
            raise ValueError("Sphere segment barrel radius must be less than its curvature.")

        self._diameter = diameter
        self._curvature = curvature
        self._thickness = curvature - sqrt(curvature * curvature - 0.25 * diameter * diameter)

        # initialise next intersection caching and control attributes
        self._further_intersection = False
        self._next_t = 0.0
        self._cached_origin = None
        self._cached_direction = None
        self._cached_ray = None

    @property
    def diameter(self):
        return self._diameter

    @diameter.setter
    def diameter(self, double diameter):

        # don't do anything if the value is unchanged
        if diameter == self._diameter:
            return

        if diameter <= 0.0:
            raise ValueError("Sphere segment barrel diameter must be positive.")

        if 0.5 * diameter > self._curvature:
            raise ValueError("Sphere segment barrel radius must be less than its curvature.")

        self._diameter = diameter
        self._thickness = self._curvature - sqrt(self._curvature * self._curvature - 0.25 * diameter * diameter)

        # the next intersection cache has been invalidated by the radius change
        self._further_intersection = False

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    @property
    def curvature(self):
        return self._curvature

    @curvature.setter
    def curvature(self, double curvature):

        # don't do anything if the value is unchanged
        if curvature == self._curvature:
            return

        if curvature <= 0.0:
            raise ValueError("Sphere segment curvature must be positive.")

        if 0.5 * self._diameter > curvature:
            raise ValueError("Sphere segment barrel radius must be less than its curvature.")

        self._curvature = curvature
        self._thickness = curvature - sqrt(curvature * curvature - 0.25 * self._diameter * self._diameter)

        # the next intersection cache has been invalidated by the radius change
        self._further_intersection = False

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    @property
    def thickness(self):
        return self._thickness

    cpdef Intersection hit(self, Ray ray):

        cdef Point3D origin
        cdef Vector3D direction
        cdef double a, b, c, t0, t1, t_closest
        cdef double t0_z, t1_z
        cdef bint t0_outside, t1_outside

        # reset further intersection state
        self._further_intersection = False

        # convert ray parameters to local space
        origin = ray.origin.transform(self.to_local())
        direction = ray.direction.transform(self.to_local())

        # coefficients of quadratic equation and discriminant
        a = direction.x * direction.x + direction.y * direction.y + direction.z * direction.z
        b = 2 * (direction.x * origin.x + direction.y * origin.y + direction.z * origin.z - direction.z * self._curvature)
        c = origin.x * origin.x + origin.y * origin.y + origin.z * origin.z - 2 * origin.z * self._curvature

        # calculate intersection distances by solving the quadratic equation
        # ray misses if there are no real roots of the quadratic
        if not solve_quadratic(a, b, c, &t0, &t1):
            return None

        # ensure t0 is always smaller than t1
        if t0 > t1:
            swap_double(&t0, &t1)

        t0_z = origin.z + t0 * direction.z
        t1_z = origin.z + t1 * direction.z

        t0_outside = t0_z > self._thickness
        t1_outside = t1_z > self._thickness

        if t0_outside and t1_outside:
            return None

        # test the intersection points inside the ray search range [0, max_distance]
        if t0 > ray.max_distance or t1 < 0.0:
            return None

        if t0 >= 0.0 and not t0_outside:
            t_closest = t0
            if t1 <= ray.max_distance and not t1_outside:
                self._further_intersection = True
                self._cached_ray = ray
                self._cached_origin = origin
                self._cached_direction = direction
                self._next_t = t1
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
        normal = new_normal3d(hit_point.x, hit_point.y, hit_point.z - self._curvature)
        normal = normal.normalise()

        if direction.dot(normal) > 0:
            normal = -normal

        # if 0 <= origin.z <= self._thickness:
        #     if origin.x * origin.x + origin.y * origin.y + (origin.z - self._curvature) * (origin.z - self._curvature) <= self._curvature * self._curvature:
        #         normal = -normal
        
        # if origin.z > self._thickness:
        #     if sqrt(origin.x * origin.x + origin.y * origin.y) <= 0.5 * self._diameter * (1 + (origin.z - self._thickness) / (self._curvature - self._thickness)):
        #         normal = -normal

        # calculate points inside and outside of surface for daughter rays to
        # spawn from - these points are displaced from the surface to avoid
        # re-hitting the same surface
        delta_x = EPSILON * normal.x
        delta_y = EPSILON * normal.y
        delta_z = EPSILON * normal.z

        inside_point = new_point3d(hit_point.x - delta_x, hit_point.y - delta_y, hit_point.z - delta_z)
        outside_point = new_point3d(hit_point.x + delta_x, hit_point.y + delta_y, hit_point.z + delta_z)

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

        if z < 0 or z > self._thickness:
            return False

        distance_sqr = (x * x + y * y + (z - self._curvature) * (z - self._curvature))

        return distance_sqr <= self._curvature * self._curvature

    cpdef BoundingBox3D bounding_box(self):

        cdef:
            BoundingBox3D box
            list points
            Point3D point

        box = BoundingBox3D()
        box.lower = new_point3d(-0.5 * self._diameter, -0.5 * self._diameter, 0)
        box.upper = new_point3d(0.5 * self._diameter, 0.5 * self._diameter, self._thickness)

        points = box.vertices()

        box = BoundingBox3D()
        for point in points:
            box.extend(point.transform(self.to_root()), BOX_PADDING)

        return box

    cpdef BoundingSphere3D bounding_sphere(self):
        cdef Point3D centre = new_point3d(0, 0, self._thickness).transform(self.to_root())
        return BoundingSphere3D(centre, 0.5 * self._diameter * SPHERE_PADDING)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return SphereSegment(self._diameter, self._curvature, parent, transform, material, name)
