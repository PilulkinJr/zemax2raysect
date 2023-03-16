from typing import List

import numpy as np

from raysect.core import Point3D, Primitive
from raysect.optical.loggingray import LoggingRay


def sample_rays_fan(
    ray_origin: Point3D,
    target_primitive: Primitive,
    sample_points: np.ndarray,
    **loggingray_kwargs,
) -> List[LoggingRay]:
    if not isinstance(sample_points, np.ndarray):
        sample_points = np.array(sample_points, dtype=np.float64)

    if sample_points.ndim != 2 and sample_points.shape[1] != 2:
        raise IndexError(f"sample_points has to have shape (N, 2), got {sample_points.shape}")

    rays: List[LoggingRay] = []

    for x, y in sample_points:

        target_point = Point3D(x, y, 0).transform(target_primitive.to_root())
        ray_direction = ray_origin.vector_to(target_point).normalise()
        ray = LoggingRay(ray_origin, ray_direction, **loggingray_kwargs)
        rays.append(ray)

    return rays


def sample_rays_parallel(
    ray_origin: Point3D,
    target_primitive: Primitive,
    sample_points: np.ndarray,
    **loggingray_kwargs,
) -> List[LoggingRay]:
    if not isinstance(sample_points, np.ndarray):
        sample_points = np.array(sample_points, dtype=np.float64)

    if sample_points.ndim != 2 and sample_points.shape[1] != 2:
        raise IndexError(f"sample_points has to have shape (N, 2), got {sample_points.shape}")

    rays: List[LoggingRay] = []

    target_point = Point3D().transform(target_primitive.to_root())
    ray_direction = ray_origin.vector_to(target_point).normalise()
    u = ray_direction.orthogonal().normalise()
    v = ray_direction.cross(u).normalise()

    for x, y in sample_points:

        _ray_origin = ray_origin + x * u + y * v
        ray = LoggingRay(_ray_origin, ray_direction, **loggingray_kwargs)
        rays.append(ray)

    return rays
