"""
A standalone replacement for `colorspacious.cspace_convert()`, covering only
the conversions used by `generate_palette()`:

    * ('sRGB1',     'CAM02-UCS')
    * ('sRGB255',   'CAM02-UCS')
    * ('CAM02-UCS', 'JCh')
    * ('CAM02-UCS', 'sRGB1')

It is a faithful port of the relevant pieces of colorspacious
(github.com/njsmith/colorspacious, MIT license, (C) Nathaniel J. Smith),
using the fixed sRGB viewing conditions and the CAM02-UCS parameters that
colorspacious uses for these named color spaces. It reproduces colorspacious's
numeric output for these routes, but does not support any other conversion.
"""

import numpy as np

__all__ = ['cspace_convert']

# ---------------------------------------------------------------------------
# sRGB <-> linear-sRGB <-> XYZ100   (from colorspacious/basics.py)
# ---------------------------------------------------------------------------

# Exact matrix from IEC 61966-2-1:1999
_XYZ100_to_sRGB1_matrix = np.array([
    [ 3.2406, -1.5372, -0.4986],
    [-0.9689,  1.8758,  0.0415],
    [ 0.0557, -0.2040,  1.0570]])
_sRGB1_to_XYZ100_matrix = np.linalg.inv(_XYZ100_to_sRGB1_matrix)


def _srgb_to_linear(c):
    c = np.asarray(c, dtype=float)
    out = np.empty(c.shape, dtype=float)
    lin = c < 0.04045
    a = 0.055
    out[lin] = c[lin] / 12.92
    out[~lin] = ((c[~lin] + a) / (a + 1)) ** 2.4
    return out


def _linear_to_srgb(c):
    c = np.asarray(c, dtype=float)
    out = np.empty(c.shape, dtype=float)
    lin = c <= 0.0031308
    a = 0.055
    out[lin] = c[lin] * 12.92
    out[~lin] = (1 + a) * c[~lin] ** (1 / 2.4) - a
    return out


def _matvec(mat, vecs):
    # mat @ each trailing-3 vector of `vecs`
    return np.einsum('...ij,...j->...i', mat, vecs)


def _sRGB1_to_XYZ100(sRGB1):
    return _matvec(_sRGB1_to_XYZ100_matrix, _srgb_to_linear(sRGB1)) * 100.0


def _XYZ100_to_sRGB1(XYZ100):
    lin = _matvec(_XYZ100_to_sRGB1_matrix, np.asarray(XYZ100, float) / 100.0)
    return _linear_to_srgb(lin)


# ---------------------------------------------------------------------------
# CIECAM02 viewing conditions (colorspacious's CIECAM02Space.sRGB)
#   XYZ100_w = D65, Y_b = 20, L_A = (64/pi)/5, average surround
# ---------------------------------------------------------------------------

_M_CAT02 = np.array([[ 0.7328,  0.4296, -0.1624],
                     [-0.7036,  1.6975,  0.0061],
                     [ 0.0030,  0.0136,  0.9834]])
_M_HPE = np.array([[ 0.38971,  0.68898, -0.07868],
                   [-0.22981,  1.18340,  0.04641],
                   [ 0.00000,  0.00000,  1.00000]])
_M_CAT02_inv = np.linalg.inv(_M_CAT02)
_M_HPE_M_CAT02_inv = _M_HPE @ _M_CAT02_inv
_M_CAT02_M_HPE_inv = _M_CAT02 @ np.linalg.inv(_M_HPE)


class _VC:
    """Precomputed CIECAM02 viewing-condition constants (sRGB)."""
    def __init__(self):
        XYZ_w = np.array([95.047, 100.0, 108.883])   # D65
        Y_b = 20.0
        L_A = (64.0 / np.pi) / 5.0
        F, c, N_c = 1.0, 0.69, 1.0                    # average surround

        self.c = c
        self.N_c = N_c

        RGB_w = _M_CAT02 @ XYZ_w
        D = F * (1 - (1 / 3.6) * np.exp((-L_A - 42) / 92))
        D = np.clip(D, 0, 1)
        self.D_RGB = D * XYZ_w[1] / RGB_w + 1 - D

        k = 1 / (5 * L_A + 1)
        self.F_L = (0.2 * k ** 4 * (5 * L_A)
                    + 0.1 * (1 - k ** 4) ** 2 * (5 * L_A) ** (1 / 3))
        self.n = Y_b / XYZ_w[1]
        self.z = 1.48 + np.sqrt(self.n)
        self.N_bb = 0.725 * (1 / self.n) ** 0.2
        self.N_cb = self.N_bb

        RGB_wc = self.D_RGB * RGB_w
        RGBp_w = _M_HPE_M_CAT02_inv @ RGB_wc
        tmp = ((self.F_L * RGBp_w) / 100) ** 0.42
        RGBp_aw = 400 * (tmp / (tmp + 27.13)) + 0.1
        self.A_w = (np.dot([2, 1, 1 / 20], RGBp_aw) - 0.305) * self.N_bb


_VC = _VC()


def _XYZ100_to_JCh_M(XYZ100):
    """Forward CIECAM02. Returns (J, C, h, M)."""
    vc = _VC
    XYZ100 = np.asarray(XYZ100, dtype=float)

    RGB = np.inner(XYZ100, _M_CAT02)
    RGB_C = vc.D_RGB * RGB
    RGBp = np.inner(RGB_C, _M_HPE_M_CAT02_inv)

    signs = np.sign(RGBp)
    tmp = (vc.F_L * signs * RGBp / 100) ** 0.42
    RGBp_a = signs * 400 * (tmp / (tmp + 27.13)) + 0.1

    a = np.inner(RGBp_a, [1, -12 / 11, 1 / 11])
    b = np.inner(RGBp_a, [1 / 9, 1 / 9, -2 / 9])
    h_rad = np.arctan2(b, a)
    h = np.rad2deg(h_rad) % 360

    A = (np.inner(RGBp_a, [2, 1, 1 / 20]) - 0.305) * vc.N_bb
    if np.any(A < 0):
        error_message = 'achromatic signal A was negative'
        raise ValueError(error_message)

    J = 100 * (A / vc.A_w) ** (vc.c * vc.z)
    e = (12500 / 13) * vc.N_c * vc.N_cb * (np.cos(h_rad + 2) + 3.8)
    t = (e * np.sqrt(a ** 2 + b ** 2)) / np.inner(RGBp_a, [1, 1, 21 / 20])
    C = t ** 0.9 * (J / 100) ** 0.5 * (1.64 - 0.29 ** vc.n) ** 0.73
    M = C * vc.F_L ** 0.25
    return J, C, h, M


def _JMh_to_XYZ100(J, M, h):
    """Inverse CIECAM02 from (J, M, h). Port of the J/M/h path only."""
    vc = _VC
    J = np.asarray(J, dtype=float)
    M = np.asarray(M, dtype=float)
    h = np.asarray(h, dtype=float)

    C = M / vc.F_L ** 0.25

    J, C, h = np.broadcast_arrays(J, C, h)
    target_shape = J.shape
    if J.ndim == 0:
        J = np.atleast_1d(J)
        C = np.atleast_1d(C)
        h = np.atleast_1d(h)

    t = (C / (np.sqrt(J / 100)
              * (1.64 - 0.29 ** vc.n) ** 0.73)) ** (1 / 0.9)
    e_t = 0.25 * (np.cos(np.deg2rad(h) + 2) + 3.8)
    A = vc.A_w * (J / 100) ** (1 / (vc.c * vc.z))

    with np.errstate(divide='ignore', invalid='ignore'):
        one_over_t = 1 / t
    one_over_t = np.select([np.isnan(one_over_t), True],
                           [np.inf, one_over_t])

    p_1 = (50000 / 13) * vc.N_c * vc.N_cb * e_t * one_over_t
    p_2 = A / vc.N_bb + 0.305
    p_3 = 21 / 20

    sin_h = np.sin(np.deg2rad(h))
    cos_h = np.cos(np.deg2rad(h))

    num = p_2 * (2 + p_3) * (460 / 1403)
    denom_part2 = (2 + p_3) * (220 / 1403)
    denom_part3 = (-27 / 1403) + p_3 * (6300 / 1403)

    a = np.empty_like(h)
    b = np.empty_like(h)
    small_cos = np.abs(sin_h) >= np.abs(cos_h)

    b[small_cos] = (num[small_cos]
                    / (p_1[small_cos] / sin_h[small_cos]
                       + denom_part2 * cos_h[small_cos] / sin_h[small_cos]
                       + denom_part3))
    a[small_cos] = b[small_cos] * cos_h[small_cos] / sin_h[small_cos]

    a[~small_cos] = (num[~small_cos]
                     / (p_1[~small_cos] / cos_h[~small_cos]
                        + denom_part2
                        + denom_part3 * sin_h[~small_cos] / cos_h[~small_cos]))
    b[~small_cos] = a[~small_cos] * sin_h[~small_cos] / cos_h[~small_cos]

    p2ab = np.stack([p_2, a, b], axis=-1)
    RGBp_a_matrix = (1 / 1403) * np.array([[460,  451,   288],
                                           [460, -891,  -261],
                                           [460, -220, -6300]], dtype=float)
    RGBp_a = np.inner(p2ab, RGBp_a_matrix)

    RGBp = (np.sign(RGBp_a - 0.1)
            * (100 / vc.F_L)
            * ((27.13 * np.abs(RGBp_a - 0.1))
               / (400 - np.abs(RGBp_a - 0.1))) ** (1 / 0.42))

    RGB_C = np.inner(RGBp, _M_CAT02_M_HPE_inv)
    RGB = RGB_C / vc.D_RGB
    XYZ100 = np.inner(RGB, _M_CAT02_inv)
    return XYZ100.reshape(target_shape + (3,))


# ---------------------------------------------------------------------------
# CAM02-UCS (Luo et al. 2006) J'a'b' <-> JMh   (KL=1.00, c1=0.007, c2=0.0228)
# ---------------------------------------------------------------------------

_UCS_KL, _UCS_C1, _UCS_C2 = 1.00, 0.007, 0.0228


def _JMh_to_Jpapbp(JMh):
    JMh = np.asarray(JMh, dtype=float)
    J = JMh[..., 0]
    M = JMh[..., 1]
    h = JMh[..., 2]
    Jp = (1 + 100 * _UCS_C1) * J / (1 + _UCS_C1 * J) / _UCS_KL
    Mp = (1 / _UCS_C2) * np.log(1 + _UCS_C2 * M)
    h_rad = np.deg2rad(h)
    ap = Mp * np.cos(h_rad)
    bp = Mp * np.sin(h_rad)
    return np.stack([Jp, ap, bp], axis=-1)


def _Jpapbp_to_JMh(Jpapbp):
    Jpapbp = np.asarray(Jpapbp, dtype=float)
    Jp = Jpapbp[..., 0] * _UCS_KL
    ap = Jpapbp[..., 1]
    bp = Jpapbp[..., 2]
    J = -Jp / (_UCS_C1 * Jp - 100 * _UCS_C1 - 1)
    Mp = np.hypot(ap, bp)
    h = np.rad2deg(np.arctan2(bp, ap)) % 360
    M = (np.exp(_UCS_C2 * Mp) - 1) / _UCS_C2
    return np.stack([J, M, h], axis=-1)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def cspace_convert(arr, start, end):
    """Drop-in replacement for `colorspacious.cspace_convert()`, restricted to
    the start-end pairs used by `generate_palette()`. Raises for anything
    else."""
    route = (start, end)

    if route == ('sRGB1', 'CAM02-UCS'):
        J, C, h, M = _XYZ100_to_JCh_M(_sRGB1_to_XYZ100(arr))
        return _JMh_to_Jpapbp(np.stack([J, M, h], axis=-1))

    if route == ('sRGB255', 'CAM02-UCS'):
        sRGB1 = np.asarray(arr, dtype=float) / 255.0
        J, C, h, M = _XYZ100_to_JCh_M(_sRGB1_to_XYZ100(sRGB1))
        return _JMh_to_Jpapbp(np.stack([J, M, h], axis=-1))

    if route == ('CAM02-UCS', 'JCh'):
        JMh = _Jpapbp_to_JMh(arr)
        XYZ100 = _JMh_to_XYZ100(JMh[..., 0], JMh[..., 1], JMh[..., 2])
        J, C, h, M = _XYZ100_to_JCh_M(XYZ100)
        return np.stack([J, C, h], axis=-1)

    if route == ('CAM02-UCS', 'sRGB1'):
        JMh = _Jpapbp_to_JMh(arr)
        XYZ100 = _JMh_to_XYZ100(JMh[..., 0], JMh[..., 1], JMh[..., 2])
        return _XYZ100_to_sRGB1(XYZ100)

    raise NotImplementedError