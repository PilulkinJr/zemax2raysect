from libc.math cimport sqrt, fabs

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


cdef class Rectangle(Primitive):

    def __init__(
        self,
        double width=1.0,
        double height=1.0,
        object parent=None,
        AffineMatrix3D transform=None,
        Material material=None,
        str name=None
    ):

        if width <= 0:
            raise ValueError("Rectangle width must be positive.")

        if height <= 0:
            raise ValueError("Rectangle height must be positive.")

        super().__init__(parent, transform, material, name)

        self._width = width
        self._height = height

    @property
    def width(self):
        return self._width

    @width.setter
    def width(self, double value):

        if value == self._width:
            return

        if value <= 0.0:
            raise ValueError("Rectangle width must be positive.")

        self._width = value

        # any geometry caching in the root node is now invalid, inform root
        self.notify_geometry_change()

    @property
    def height(self):
        return self._height

    @height.setter
    def height(self, double value):

        if value == self._height:
            return

        if value <= 0.0:
            raise ValueError("Rectangle height must be positive.")

        self._height = value

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

        if fabs(t_x) > 0.5 * self._width or fabs(t_y) > 0.5 * self._height:
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

        # convert world space point to local space
        local_point = point.transform(self.to_local())

        if local_point.z != 0:
            return False

        return fabs(local_point.x) <= 0.5 * self._width and fabs(local_point.y) <= 0.5 * self._height

    cpdef BoundingBox3D bounding_box(self):

        cdef:
            BoundingBox3D box
            list points
            Point3D point

        box = BoundingBox3D()
        box.lower = new_point3d(-0.5 * self._width, -0.5 * self._height, 0)
        box.upper = new_point3d(0.5 * self._width, 0.5 * self._height, 0)

        points = box.vertices()

        box = BoundingBox3D()
        for point in points:
            box.extend(point.transform(self.to_root()), BOX_PADDING)

        return box

    cpdef BoundingSphere3D bounding_sphere(self):
        cdef Point3D centre = new_point3d(0, 0, 0).transform(self.to_root())
        cdef double radius = 0.5 * sqrt(self._width * self._width + self._height * self._height)
        return BoundingSphere3D(centre, radius * SPHERE_PADDING)

    cpdef object instance(self, object parent=None, AffineMatrix3D transform=None, Material material=None, str name=None):
        return Rectangle(self._width, self._height, parent, transform, material, name)
