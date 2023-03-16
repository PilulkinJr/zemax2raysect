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


cdef class Circle(Primitive):

    def __init__(
        self,
        double radius=0.5,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):

        if radius <= 0:
            raise ValueError("Circle radius must be positive.")

        super().__init__(parent, transform, material, name)

        self._radius = radius

    @property
    def radius(self):
        return self._radius

    @radius.setter
    def radius(self, double radius):

        # don't do anything if the value is unchanged
        if radius == self._radius:
            return

        if radius <= 0.0:
            raise ValueError("Circle radius must be positive.")

        self._radius = radius

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    cpdef Intersection hit(self, Ray ray):

        cdef Point3D origin
        cdef Vector3D direction
        cdef double t, t_x, t_y

        # convert ray parameters to local space
        origin = ray.origin.transform(self.to_local())
        direction = ray.direction.transform(self.to_local())

        if direction.z == 0:
            return None

        t = -origin.z / direction.z

        # test the intersection points inside the ray search range [0, max_distance]
        if t > ray.max_distance or t < 0.0:
            return None

        t_x = origin.x + t * direction.x
        t_y = origin.y + t * direction.y

        if t_x * t_x + t_y * t_y > self._radius * self._radius:
            return None

        return self._generate_intersection(ray, origin, direction, t)

    cpdef Intersection next_intersection(self):

        return None

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
        normal = new_normal3d(0, 0, 1)
        if origin.z < 0:
            normal = -normal

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

        if local_point.z != 0:
            return False

        distance_sqr = local_point.x * local_point.x + local_point.y * local_point.y

        return distance_sqr <= self._radius * self._radius

    cpdef BoundingBox3D bounding_box(self):

        cdef:
            BoundingBox3D box
            list points
            Point3D point

        box = BoundingBox3D()
        box.lower = new_point3d(-self._radius, -self._radius, 0)
        box.upper = new_point3d(self._radius, self._radius, 0)

        points = box.vertices()

        box = BoundingBox3D()
        for point in points:
            box.extend(point.transform(self.to_root()), BOX_PADDING)

        return box

    cpdef BoundingSphere3D bounding_sphere(self):
        cdef Point3D centre = new_point3d(0, 0, 0).transform(self.to_root())
        return BoundingSphere3D(centre, self._radius * SPHERE_PADDING)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return Circle(self._radius, parent, transform, material, name)
