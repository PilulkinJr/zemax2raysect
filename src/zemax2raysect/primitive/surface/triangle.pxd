
from raysect.core cimport Primitive, Point3D, Vector3D, Ray, Intersection, Point2D, Vector2D

cdef class Triangle(Primitive):

    cdef:
        Point2D _a, _b, _c
        Vector2D _u, _v, _r
        double _area

    cdef Intersection _generate_intersection(self, Ray ray, Point3D origin, Vector3D direction, double ray_distance)
