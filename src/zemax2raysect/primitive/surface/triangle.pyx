from libc.math cimport sqrt, fabs, hypot

from raysect.core cimport (
    Material,
    new_intersection,
    BoundingBox3D,
    BoundingSphere3D,
    new_point3d,
    new_normal3d,
    Normal3D,
    AffineMatrix3D,
    new_vector2d,
)
from raysect.core.math.cython cimport solve_quadratic, swap_double

# bounding box and sphere are padded by small amounts to avoid numerical accuracy issues
DEF BOX_PADDING = 1e-9
DEF SPHERE_PADDING = 1.000000001

# additional ray distance to avoid re-hitting the same surface point
DEF EPSILON = 1e-9


cdef class Triangle(Primitive):

    def __init__(
        self,
        Point2D a=Point2D(0, 0),
        Point2D b=Point2D(1, 0),
        Point2D c=Point2D(0, 1),
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):

        self._u = new_vector2d(b.x - a.x, b.y - a.y)
        self._v = new_vector2d(c.x - a.x, c.y - a.y)
        self._r = new_vector2d(c.x - b.x, c.y - b.y)
        self._area = 0.5 * self._u.cross(self._v)

        if self._area == 0:
            raise ValueError

        super().__init__(parent, transform, material, name)

        self._a = a
        self._b = b
        self._c = c

    @property
    def area(self):
        return fabs(self._area)

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

        if not self.contains(new_point3d(t_x, t_y, 0)):
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
        cdef Vector2D tmp
        cdef double alpha, beta

        # convert world space point to local space
        local_point = point.transform(self.to_local())

        if local_point.z != 0:
            return False

        tmp = new_vector2d(local_point.x, local_point.y)

        alpha = tmp.cross(self._u) / (2 * self._area)
        if alpha < 0 or alpha > 1:
            return False

        beta = tmp.cross(self._v) / (2 * self._area)
        if beta < 0 or beta > 1:
            return False

        if alpha + beta > 1:
            return False

        return True

    cpdef BoundingBox3D bounding_box(self):

        cdef:
            BoundingBox3D box
            list points
            Point3D point

        box = BoundingBox3D()
        box.lower = new_point3d(min(self._a.x, self._b.x, self._c.x), min(self._a.y, self._b.y, self._c.y), 0)
        box.upper = new_point3d(max(self._a.x, self._b.x, self._c.x), max(self._a.y, self._b.y, self._c.y), 0)

        points = box.vertices()

        box = BoundingBox3D()
        for point in points:
            box.extend(point.transform(self.to_root()), BOX_PADDING)

        return box


    cpdef BoundingSphere3D bounding_sphere(self):

        cdef:
            double len_u2 = self._u.x * self._u.x + self._u.y * self._u.y
            double len_v2 = self._v.x * self._v.x + self._v.y * self._v.y
            double centre_x = (self._v.y * len_u2 - self._u.y * len_v2) / (2 * self._area)
            double centre_y = (self._u.x * len_v2 - self._v.x * len_u2) / (2 * self._area)
            double radius = self._u.get_length() * self._v.get_length() * self._r.get_length() / (4 * self._area)
            Point3D centre = new_point3d(centre_x, centre_y, 0).transform(self.to_root())

        return BoundingSphere3D(centre, radius * SPHERE_PADDING)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return Triangle(self._a, self._b, self._c, parent, transform, material, name)
