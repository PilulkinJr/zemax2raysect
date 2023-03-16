from typing import Tuple

import numpy as np

from raysect.core import (
    AffineMatrix3D,
    BoundingBox3D,
    Intersection,
    Material,
    Point3D,
    Primitive,
    Ray,
    Vector3D,
)


def _solve_quartic(a: float, b: float, c: float, d: float, e: float) -> Tuple[float]:

    roots = np.roots((a, b, c, d, e))
    result = []

    for z in roots:
        if abs(z.imag) < 1.0e-6 * abs(z.real) and z.real >= 0:
            result.append(z.real)

    result.sort()
    return tuple(result)


class Torus(Primitive):
    def __init__(
        self: "Torus",
        radius_major: float = 2.0,
        radius_minor: float = 1.0,
        material: Material = None,
        parent: object = None,
        transform: AffineMatrix3D = None,
        name: str = "",
    ) -> None:

        if radius_major <= 0:
            raise ValueError

        if radius_minor <= 0:
            raise ValueError

        self._radius_major = radius_major
        self._radius_minor = radius_minor

        self._further_intersection: bool = False
        self._cached_origin: Point3D = None
        self._cached_direction: Vector3D = None
        self._cached_ray: Ray = None
        self._cached_t: Tuple[float] = None
        self._next_t: float = None

    def hit(self: "Torus", ray: Ray) -> Intersection:

        self._further_intersection = False

        origin = ray.origin.transform(self.to_local())
        direction = ray.direction.transform(self.to_local())

        o2x, o2y, o2z = origin.x * origin.x, origin.y * origin.y, origin.z * origin.z
        d2x, d2y, d2z = (
            direction.x * direction.x,
            direction.y * direction.y,
            direction.z * direction.z,
        )

        r2maj = self._radius_major * self._radius_major
        r2min = self._radius_minor * self._radius_minor
        xi = r2maj - r2min
        ix = r2maj + r2min

        alpha = d2x + d2y + d2z
        beta = origin.x * direction.x + origin.y * direction.y + origin.z * direction.z
        gamma = o2x + o2y + o2z
        delta = gamma + xi
        sigma = gamma - ix

        a = alpha * alpha
        b = 4.0 * alpha * beta
        c = 2.0 * alpha * delta - 4.0 * r2maj * (d2x + d2z) + 4.0 * beta * beta
        d = 8.0 * r2maj * origin.y * direction.y + 4.0 * beta * sigma
        e = gamma * gamma + xi * xi - 2.0 * ((o2x + o2z) * ix - o2y * xi)

        ts = _solve_quartic(a, b, c, d, e)

        if len(ts) < 2:
            return

        t0, t1, *self._cached_t = ts
