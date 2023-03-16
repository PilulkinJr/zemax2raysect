# cython: language_level=3

from libc.math cimport sqrt, cos, acos, sqrt, pow, pi, isnan
from libc.complex cimport creal, cimag, csqrt, cabs
cimport cython

import numpy as np
cimport numpy as np

np.import_array()


@cython.cdivision(True)
cdef bint solve_cubic(double a3, double a2, double a1, double a0, double complex *t0, double complex *t1, double complex *t2):
    """Solve qubic equation.

    .. math::
        a3 * x^3 + a2 * x2 + a1 * x + a0 = 0

    t0 is always the greatest real root. t1 and t2 are real or complex conjugate.
    Returns True in case of all real roots and False otherwise.
        
    :param double a3, a2, a1, a0: Polynomial coefficients.
    :param double complex* t0, t1, t2: Roots.
    """
    cdef:
        double q, r, d
        double alpha, t
        double x1, x2, y2
        double theta, psi1, psi2, psi3
    
    a2 = a2 / a3
    a1 = a1 / a3
    a0 = a0 / a3
    
    q = a1 / 3.0 - a2 * a2 / 9.0
    r = (a1 * a2 - 3.0 * a0) / 6.0 - a2 * a2 * a2 / 27.0
    d = r * r + q * q * q

    # First case -- one real root and two complex conjugate.
    if d > 0.0:
        
        alpha = pow(abs(r) + sqrt(d), 1.0 / 3.0)
        t = alpha - q / alpha
        if r < 0:
            t = q / alpha - alpha
            
        x1 = t - a2 / 3.0
        x2 = -0.5 * t - a2 / 3.0
        y2 = 0.5 * sqrt(3.0) * (alpha + q / alpha)
        
        t0[0] = x1
        t1[0] = x2 + y2 * 1j
        t2[0] = x2 - y2 * 1j

        return False
                
    # Second case -- three real roots.
    theta = 0
    if q < 0:
        theta = acos(r / sqrt(-q * q * q))
        
    phi1 = theta / 3.0
    phi2 = phi1 - 2.0 * pi / 3.0
    phi3 = phi1 + 2.0 * pi / 3.0
    
    x1 = 2.0 * sqrt(-q) * cos(phi1) - a2 / 3.0
    x2 = 2.0 * sqrt(-q) * cos(phi2) - a2 / 3.0
    x3 = 2.0 * sqrt(-q) * cos(phi3) - a2 / 3.0
    
    t0[0] = x3
    t1[0] = x2
    t2[0] = x1

    return True


# @cython.cdivision(True)
# cdef bint solve_quartic(
#     double a4,
#     double a3,
#     double a2,
#     double a1,
#     double a0,
#     double complex *t0,
#     double complex *t1,
#     double complex *t2,
#     double complex *t3,
# ):
#     """Solve quatric equation.

#     .. math::
#         a4 * x^4 + a3 * x^3 + a2 * x2 + a1 * x + a0 = 0

#     Returns True if all roots are real, False -- otherwise.

#     :param double a4, a3, a2, a1, a0: Polynomial coefficients.
#     :param double complex* t0, t1, t2, t4: Roots.
#     """
#     cdef:
#         double c, b0, b1, b2, sigma
#         double complex q1, q2, q3
#         double complex alpha, beta, gamma
        
#     a3 = a3 / a4
#     a2 = a2 / a4
#     a1 = a1 / a4
#     a0 = a0 / a4
        
#     c = 0.25 * a3
#     b2 = a2 - 6 * c**2
#     b1 = a1 - 2 * a2 * c + 8 * c**3
#     b0 = a0 - a1 * c + a2 * c**2 - 3.0 * c**4
    
#     sigma = -1
#     if b1 > 0:
#         sigma = 1
    
#     solve_cubic(1.0, 0.5 * b2, (b2**2 - 4.0 * b0) / 16.0, -b1**2 / 64.0, &q1, &q2, &q3)
    
#     # if creal(q1) < 1e-15:
#     #     q1 = 0 + 0j
    
#     if creal(q2) < 1e-15:
#         q2 = 0 + 0j
        
#     if creal(q3) < 1e-15:
#         q3 = 0 + 0j
    
#     if creal(q1) < 1e-15:
#         alpha = 0 + 0j
#     else:
#         alpha = csqrt(creal(q1))
        
#     if cabs(creal(q2) + creal(q3)) < 1e-15:
#         beta = 0 + 0j
#     else:
#         beta = creal(q2) + creal(q3)
    
#     if cabs(creal(q2) * creal(q3)) < 1e-15:
#         gamma = 0 + 0j
#     else:
#         gamma = 2 * sigma * csqrt(creal(q2) * creal(q3))
    
#     t0[0] = -c + alpha + csqrt(beta - gamma)
#     t1[0] = -c + alpha - csqrt(beta - gamma)
#     t2[0] = -c - alpha + csqrt(beta + gamma)
#     t3[0] = -c - alpha - csqrt(beta + gamma)

#     # if alpha >= 0 and (beta - gamma) >= 0 and (beta + gamma) >= 0:
#     #     return True
#     return False


cdef bint solve_quartic(
    double a4,
    double a3,
    double a2,
    double a1,
    double a0,
    double complex *t0,
    double complex *t1,
    double complex *t2,
    double complex *t3,
):
    """Solve quatric equation.

    .. math::
        a4 * x^4 + a3 * x^3 + a2 * x2 + a1 * x + a0 = 0

    Returns True if all roots are real, False -- otherwise.
    Uses numpy.roots.

    :param double a4, a3, a2, a1, a0: Polynomial coefficients.
    :param double complex* t0, t1, t2, t4: Roots.
    """
    cdef:
        np.ndarray[np.complex128_t, ndim=1] roots = np.roots((a4, a3, a2, a1, a0)).astype(np.complex128)
        double complex[:] roots_mv = roots

    t0[0] = roots_mv[0]
    t1[0] = roots_mv[1]
    t2[0] = roots_mv[2]
    t3[0] = roots_mv[3]

    if np.all(np.imag(roots) == 0):
        return True

    return False
