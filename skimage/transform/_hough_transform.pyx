#cython: cdivision=True
#cython: boundscheck=False
#cython: nonecheck=False
#cython: wraparound=False
import numpy as np

cimport numpy as cnp
cimport cython

from libc.math cimport abs, fabs, sqrt, ceil
from libc.stdlib cimport rand

from skimage.draw import circle_perimeter

cdef double PI_2 = 1.5707963267948966
cdef double NEG_PI_2 = -PI_2


cdef inline Py_ssize_t round(double r):
    return <Py_ssize_t>((r + 0.5) if (r > 0.0) else (r - 0.5))


def hough_circle(cnp.ndarray img,
                 cnp.ndarray[ndim=1, dtype=cnp.intp_t] radius,
                 char normalize=True, char full_output=False):
    """Perform a circular Hough transform.

    Parameters
    ----------
    img : (M, N) ndarray
        Input image with nonzero values representing edges.
    radius : ndarray
        Radii at which to compute the Hough transform.
    normalize : boolean, optional (default True)
        Normalize the accumulator with the number
        of pixels used to draw the radius.
    full_output : boolean, optional (default False)
        Extend the output size by twice the largest
        radius in order to detect centers outside the
        input picture.

    Returns
    -------
    H : 3D ndarray (radius index, (M + 2R, N + 2R) ndarray)
        Hough transform accumulator for each radius.
        R designates the larger radius if full_output is True.
        Otherwise, R = 0.
    """
    if img.ndim != 2:
        raise ValueError('The input image must be 2D.')

    cdef Py_ssize_t xmax = img.shape[0]
    cdef Py_ssize_t ymax = img.shape[1]

    # compute the nonzero indexes
    cdef cnp.ndarray[ndim=1, dtype=cnp.intp_t] x, y
    x, y = np.nonzero(img)

    cdef Py_ssize_t num_pixels = x.size

    cdef Py_ssize_t offset = 0
    if full_output:
        # Offset the image
        offset = radius.max()
        x = x + offset
        y = y + offset

    cdef Py_ssize_t i, p, c, num_circle_pixels, tx, ty
    cdef double incr
    cdef cnp.ndarray[ndim=1, dtype=cnp.intp_t] circle_x, circle_y

    cdef cnp.ndarray[ndim=3, dtype=cnp.double_t] acc = \
         np.zeros((radius.size,
                   img.shape[0] + 2 * offset,
                   img.shape[1] + 2 * offset), dtype=np.double)

    for i, rad in enumerate(radius):
        # Store in memory the circle of given radius
        # centered at (0,0)
        circle_x, circle_y = circle_perimeter(0, 0, rad)

        num_circle_pixels = circle_x.size

        if normalize:
            incr = 1.0 / num_circle_pixels
        else:
            incr = 1

        # For each non zero pixel
        for p in range(num_pixels):
            # Plug the circle at (px, py),
            # its coordinates are (tx, ty)
            for c in range(num_circle_pixels):
                tx = circle_x[c] + x[p]
                ty = circle_y[c] + y[p]
                if offset:
                    acc[i, tx, ty] += incr
                elif 0 <= tx < xmax and 0 <= ty < ymax:
                    acc[i, tx, ty] += incr

    return acc


def hough_ellipse(cnp.ndarray img, int threshold=4, double accuracy=1,
                  int min_size=4, max_size=None):
    """Perform an elliptical Hough transform.

    Parameters
    ----------
    img : (M, N) ndarray
        Input image with nonzero values representing edges.
    threshold: int, optional (default 4)
        Accumulator threshold value.
    accuracy : double, optional (default 1)
        Bin size on the minor axis used in the accumulator.
    min_size : int, optional (default 4)
        Minimal major axis length.
    max_size : int, optional
        Maximal minor axis length. (default None)
        If None, the value is set to the half of the smaller
        image dimension.

    Returns
    -------
    res : list of tuples [(x0, y0, a, b, angle, accumulator)]
          Where (x0, y0) is the center, (a, b) major and minor axis.
          The angle value follows `draw.ellipse_perimeter()` convention.

    Examples
    --------
    >>> img = np.zeros((25, 25), dtype=int)
    >>> rr, cc = draw.ellipse_perimeter(10, 10, 6, 8)
    >>> img[rr, cc] = 1
    >>> result = hough_ellipse(img, threshold=6)
    [(10.0, 10.0, 8.0, 6.0474292058692187, 0.0, 8)]

    Notes
    -----
    The accuracy must be chosen to produce a peak in the accumulator
    distribution. In other words, a flat accumulator distribution with low
    values may be caused by a too low bin size.

    References
    ----------
    .. [1] Xie, Yonghong, and Qiang Ji. "A new efficient ellipse detection
           method." Pattern Recognition, 2002. Proceedings. 16th International
           Conference on. Vol. 2. IEEE, 2002
    """
    if img.ndim != 2:
            raise ValueError('The input image must be 2D.')

    cdef long[:, :] pixels = np.transpose(np.nonzero(img))
    cdef Py_ssize_t num_pixels = pixels.shape[0]
    cdef list acc = list()
    cdef list results = list()
    cdef bin_size = accuracy**2

    cdef int max_b_squared
    if max_size is None:
        if img.shape[0] < img.shape[1]:
            max_b_squared = np.round(0.5 * img.shape[0])**2
        else:
            max_b_squared = np.round(0.5 * img.shape[1])**2
    else:
        max_b_squared = max_size**2

    cdef Py_ssize_t p1, p2, p3, p1x, p1y, p2x, p2y, p3x, p3y
    cdef double x0, y0, a, b, d, k
    cdef double cos_tau_squared, b_squared, f_squared, angle

    for p1 in range(num_pixels):
        p1x = pixels[p1, 1]
        p1y = pixels[p1, 0]

        for p2 in range(p1):
            p2x = pixels[p2, 1]
            p2y = pixels[p2, 0]

            # Candidate: center (x0, y0) and main axis a
            a = 0.5 * sqrt((p1x - p2x)**2 + (p1y - p2y)**2)
            if a > 0.5 * min_size:
                x0 = 0.5 * (p1x + p2x)
                y0 = 0.5 * (p1y + p2y)

                for p3 in range(num_pixels):
                    p3x = pixels[p3, 1]
                    p3y = pixels[p3, 0]

                    d = sqrt((p3x - x0)**2 + (p3y - y0)**2)
                    if d > min_size:
                        f_squared = (p3x - p1x)**2 + (p3y - p1y)**2
                        cos_tau_squared = ((a**2 + d**2 - f_squared) \
                                           / (2 * a * d))**2
                        # Consider b2 > 0 and avoid division by zero
                        k = a**2 - d**2 * cos_tau_squared
                        if k > 0 and cos_tau_squared < 1:
                            b_squared = a**2 * d**2 * (1 - cos_tau_squared) / k
                            # b2 range is limited to avoid histogram memory
                            # overflow
                            if b_squared <= max_b_squared:
                                acc.append(b_squared)

                if len(acc) > 0:
                    bins = np.arange(0, np.max(acc) + bin_size, bin_size)
                    hist, bin_edges = np.histogram(acc, bins=bins)
                    hist_max = np.max(hist)
                    if hist_max > threshold:
                        angle = np.arctan2(p1x - p2x, p1y - p2y)
                        # pi - angle to keep ellipse_perimeter() convention
                        if angle != 0:
                            angle = np.pi - angle
                        b = sqrt(bin_edges[hist.argmax()])
                        results.append((x0,
                                        y0,
                                        a,
                                        b,
                                        angle,
                                        hist_max,  # Accumulator
                                        ))
                    acc = []

    return results


def hough_line(cnp.ndarray img,
               cnp.ndarray[ndim=1, dtype=cnp.double_t] theta=None):
    """Perform a straight line Hough transform.

    Parameters
    ----------
    img : (M, N) ndarray
        Input image with nonzero values representing edges.
    theta : 1D ndarray of double
        Angles at which to compute the transform, in radians.
        Defaults to -pi/2 .. pi/2

    Returns
    -------
    H : 2-D ndarray of uint64
        Hough transform accumulator.
    theta : ndarray
        Angles at which the transform was computed, in radians.
    distances : ndarray
        Distance values.

    Notes
    -----
    The origin is the top left corner of the original image.
    X and Y axis are horizontal and vertical edges respectively.
    The distance is the minimal algebraic distance from the origin
    to the detected line.

    Examples
    --------
    Generate a test image:

    >>> img = np.zeros((100, 150), dtype=bool)
    >>> img[30, :] = 1
    >>> img[:, 65] = 1
    >>> img[35:45, 35:50] = 1
    >>> for i in range(90):
    ...     img[i, i] = 1
    >>> img += np.random.random(img.shape) > 0.95

    Apply the Hough transform:

    >>> out, angles, d = hough_line(img)

    .. plot:: hough_tf.py

    """
    if img.ndim != 2:
        raise ValueError('The input image must be 2D.')

    # Compute the array of angles and their sine and cosine
    cdef cnp.ndarray[ndim=1, dtype=cnp.double_t] ctheta
    cdef cnp.ndarray[ndim=1, dtype=cnp.double_t] stheta

    if theta is None:
        theta = np.linspace(NEG_PI_2, PI_2, 180)

    ctheta = np.cos(theta)
    stheta = np.sin(theta)

    # compute the bins and allocate the accumulator array
    cdef cnp.ndarray[ndim=2, dtype=cnp.uint64_t] accum
    cdef cnp.ndarray[ndim=1, dtype=cnp.double_t] bins
    cdef Py_ssize_t max_distance, offset

    max_distance = 2 * <Py_ssize_t>ceil(sqrt(img.shape[0] * img.shape[0] +
                                             img.shape[1] * img.shape[1]))
    accum = np.zeros((max_distance, theta.shape[0]), dtype=np.uint64)
    bins = np.linspace(-max_distance / 2.0, max_distance / 2.0, max_distance)
    offset = max_distance / 2

    # compute the nonzero indexes
    cdef cnp.ndarray[ndim=1, dtype=cnp.npy_intp] x_idxs, y_idxs
    y_idxs, x_idxs = np.nonzero(img)

    # finally, run the transform
    cdef Py_ssize_t nidxs, nthetas, i, j, x, y, accum_idx
    nidxs = y_idxs.shape[0]  # x and y are the same shape
    nthetas = theta.shape[0]
    for i in range(nidxs):
        x = x_idxs[i]
        y = y_idxs[i]
        for j in range(nthetas):
            accum_idx = <int>round((ctheta[j] * x + stheta[j] * y)) + offset
            accum[accum_idx, j] += 1
    return accum, theta, bins


def probabilistic_hough_line(cnp.ndarray img, int threshold=10,
                             int line_length=50, int line_gap=10,
                             cnp.ndarray[ndim=1, dtype=cnp.double_t] theta=None):
    """Return lines from a progressive probabilistic line Hough transform.

    Parameters
    ----------
    img : (M, N) ndarray
        Input image with nonzero values representing edges.
    threshold : int, optional (default 10)
        Threshold
    line_length : int, optional (default 50)
        Minimum accepted length of detected lines.
        Increase the parameter to extract longer lines.
    line_gap : int, optional, (default 10)
        Maximum gap between pixels to still form a line.
        Increase the parameter to merge broken lines more aggresively.
    theta : 1D ndarray, dtype=double, optional, default (-pi/2 .. pi/2)
        Angles at which to compute the transform, in radians.

    Returns
    -------
    lines : list
      List of lines identified, lines in format ((x0, y0), (x1, y0)),
      indicating line start and end.

    References
    ----------
    .. [1] C. Galamhos, J. Matas and J. Kittler, "Progressive probabilistic
           Hough transform for line detection", in IEEE Computer Society
           Conference on Computer Vision and Pattern Recognition, 1999.
    """
    if img.ndim != 2:
        raise ValueError('The input image must be 2D.')

    if theta is None:
        theta = PI_2 - np.arange(180) / 180.0 * 2 * PI_2

    cdef Py_ssize_t height = img.shape[0]
    cdef Py_ssize_t width = img.shape[1]

    # compute the bins and allocate the accumulator array
    cdef cnp.ndarray[ndim=2, dtype=cnp.int64_t] accum
    cdef cnp.ndarray[ndim=1, dtype=cnp.double_t] ctheta, stheta
    cdef cnp.ndarray[ndim=2, dtype=cnp.uint8_t] mask = \
         np.zeros((height, width), dtype=np.uint8)
    cdef cnp.ndarray[ndim=2, dtype=cnp.int32_t] line_end = \
         np.zeros((2, 2), dtype=np.int32)
    cdef Py_ssize_t max_distance, offset, num_indexes, index
    cdef double a, b
    cdef Py_ssize_t nidxs, i, j, x, y, px, py, accum_idx
    cdef int value, max_value, max_theta
    cdef int shift = 16
    # maximum line number cutoff
    cdef Py_ssize_t lines_max = 2 ** 15
    cdef Py_ssize_t xflag, x0, y0, dx0, dy0, dx, dy, gap, x1, y1, \
                    good_line, count
    cdef list lines = list()

    max_distance = 2 * <int>ceil((sqrt(img.shape[0] * img.shape[0] +
                                       img.shape[1] * img.shape[1])))
    accum = np.zeros((max_distance, theta.shape[0]), dtype=np.int64)
    offset = max_distance / 2
    nthetas = theta.shape[0]

    # compute sine and cosine of angles
    ctheta = np.cos(theta)
    stheta = np.sin(theta)

    # find the nonzero indexes
    y_idxs, x_idxs = np.nonzero(img)
    points = list(zip(x_idxs, y_idxs))
    # mask all non-zero indexes
    mask[y_idxs, x_idxs] = 1

    while 1:

        # quit if no remaining points
        count = len(points)
        if count == 0:
            break

        # select random non-zero point
        index = rand() % count
        x = points[index][0]
        y = points[index][1]
        del points[index]

        # if previously eliminated, skip
        if not mask[y, x]:
            continue

        value = 0
        max_value = threshold - 1
        max_theta = -1

        # apply hough transform on point
        for j in range(nthetas):
            accum_idx = <int>round((ctheta[j] * x + stheta[j] * y)) + offset
            accum[accum_idx, j] += 1
            value = accum[accum_idx, j]
            if value > max_value:
                max_value = value
                max_theta = j
        if max_value < threshold:
            continue

        # from the random point walk in opposite directions and find line
        # beginning and end
        a = -stheta[max_theta]
        b = ctheta[max_theta]
        x0 = x
        y0 = y
        # calculate gradient of walks using fixed point math
        xflag = fabs(a) > fabs(b)
        if xflag:
            if a > 0:
                dx0 = 1
            else:
                dx0 = -1
            dy0 = <int>round(b * (1 << shift) / fabs(a))
            y0 = (y0 << shift) + (1 << (shift - 1))
        else:
            if b > 0:
                dy0 = 1
            else:
                dy0 = -1
            dx0 = <int>round(a * (1 << shift) / fabs(b))
            x0 = (x0 << shift) + (1 << (shift - 1))

        # pass 1: walk the line, merging lines less than specified gap length
        for k in range(2):
            gap = 0
            px = x0
            py = y0
            dx = dx0
            dy = dy0
            if k > 0:
                dx = -dx
                dy = -dy
            while 1:
                if xflag:
                    x1 = px
                    y1 = py >> shift
                else:
                    x1 = px >> shift
                    y1 = py
                # check when line exits image boundary
                if x1 < 0 or x1 >= width or y1 < 0 or y1 >= height:
                    break
                gap += 1
                # if non-zero point found, continue the line
                if mask[y1, x1]:
                    gap = 0
                    line_end[k, 1] = y1
                    line_end[k, 0] = x1
                # if gap to this point was too large, end the line
                elif gap > line_gap:
                    break
                px += dx
                py += dy
        # confirm line length is sufficient
        good_line = abs(line_end[1, 1] - line_end[0, 1]) >= line_length or \
                    abs(line_end[1, 0] - line_end[0, 0]) >= line_length

        # pass 2: walk the line again and reset accumulator and mask
        for k in range(2):
            px = x0
            py = y0
            dx = dx0
            dy = dy0
            if k > 0:
                dx = -dx
                dy = -dy
            while 1:
                if xflag:
                    x1 = px
                    y1 = py >> shift
                else:
                    x1 = px >> shift
                    y1 = py
                # if non-zero point found, continue the line
                if mask[y1, x1]:
                    if good_line:
                        accum_idx = <int>round((ctheta[j] * x1 \
                                                + stheta[j] * y1)) + offset
                        accum[accum_idx, max_theta] -= 1
                        mask[y1, x1] = 0
                # exit when the point is the line end
                if x1 == line_end[k, 0] and y1 == line_end[k, 1]:
                    break
                px += dx
                py += dy

        # add line to the result
        if good_line:
            lines.append(((line_end[0, 0], line_end[0, 1]),
                          (line_end[1, 0], line_end[1, 1])))
            if len(lines) > lines_max:
                return lines

    return lines
