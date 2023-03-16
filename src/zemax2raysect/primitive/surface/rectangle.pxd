from raysect.core cimport Primitive, Point3D, Vector3D, Ray, Intersection

cdef class Rectangle(Primitive):

    cdef double _width, _height

    cdef Intersection _generate_intersection(self, Ray ray, Point3D origin, Vector3D direction, double ray_distance)


