from raysect.core cimport Primitive, Point3D, Vector3D, Ray, Intersection

cdef class CylinderSegment(Primitive):

    cdef double _width, _curvature, _curve_thickness, _height
    cdef bint _further_intersection
    cdef double _next_t
    cdef Point3D _cached_origin
    cdef Vector3D _cached_direction
    cdef Ray _cached_ray

    cdef Intersection _generate_intersection(self, Ray ray, Point3D origin, Vector3D direction, double ray_distance)
