from cython.parallel cimport parallel, prange, threadid
from libcpp.cmath cimport log1p
from libcpp.pair cimport pair
from libcpp.vector cimport vector
from .cyutils cimport get_thread_offset, numeric, signed_integer, \
    uninitialized_vector


def normalize_csr(const numeric[::1] data,
                  const signed_integer[::1] indices,
                  const signed_integer[::1] indptr,
                  char[::1] QC_column,
                  float[::1] normalized_data,
                  unsigned long long[::1] row_sums,
                  const unsigned long long num_cells,
                  const unsigned method_number,
                  unsigned num_threads):

    cdef bint has_QC_column = QC_column.shape[0] != 0
    cdef unsigned i, thread_index
    cdef unsigned long long row_sum, j, num_QCed_cells, thread_total_sum, \
        thread_num_QCed_cells, total_sum = 0
    cdef float normalization_factor, new_normalization_factor, \
        new_inverse_size_factor, new_row_sum, new_total_sum = 0
    cdef volatile float inverse_size_factor, new_normalization_factor_volatile
    cdef pair[unsigned, unsigned] row_range
    cdef uninitialized_vector[unsigned] thread_nums_QCed_cells
    cdef uninitialized_vector[unsigned long long] row_sums_buffer, \
        thread_total_sums
    cdef uninitialized_vector[float] new_row_sums, new_row_sums_contiguous

    num_threads = min(num_threads, num_cells)
    if num_threads <= 1:
        # Step 1a and 1b: calculate row sums and the normalization factor for
        # the size factor calculation
        if method_number == 0:  # 'logCP10k'
            # Just calculate the row sums, and use a constant normalization
            # factor of 10,000
            for i in range(num_cells):
                row_sum = 0
                for j in range(<unsigned long long> indptr[i],
                               <unsigned long long> indptr[i + 1]):
                    row_sum += <unsigned long long> data[j]
                row_sums[i] = row_sum
            normalization_factor = 10000
        else:
            # Same as the logCP10k version, but take the mean of the row sums
            # (across cells passing QC, if `QC_column` was specified) as the
            # size factor
            if not has_QC_column:
                for i in range(num_cells):
                    row_sum = 0
                    for j in range(<unsigned long long> indptr[i],
                                   <unsigned long long> indptr[i + 1]):
                        row_sum += <unsigned long long> data[j]
                    row_sums[i] = row_sum
                    total_sum += row_sum
                num_QCed_cells = num_cells
            else:
                num_QCed_cells = 0
                for i in range(num_cells):
                    row_sum = 0
                    for j in range(<unsigned long long> indptr[i],
                                   <unsigned long long> indptr[i + 1]):
                        row_sum += <unsigned long long> data[j]
                    row_sums[i] = row_sum
                    if QC_column[i]:
                        total_sum += row_sum
                        num_QCed_cells += 1
            normalization_factor = <float> total_sum / num_QCed_cells

        if method_number != 2:  # 'logCP10k' and 'log1pPF'
            # Step 1c and 2: calculate each cell's inverse size factor and
            # multiply all counts for that cell by it, then log1p-transform.
            # Declare `inverse_size_factor` as volatile to force it to be
            # calculated explicitly.
            for i in range(num_cells):
                inverse_size_factor = normalization_factor / row_sums[i]
                for j in range(<unsigned long long> indptr[i],
                               <unsigned long long> indptr[i + 1]):
                    normalized_data[j] = log1p(data[j] * inverse_size_factor)
        else:  # 'PFlog1pPF'
            # Step 1c, 2, and 3a: in addition to calculating each cell's
            # size factor and multiplying the counts by it, also calculate
            # the new row sums and total sum for a second round of proportional
            # fitting. To ensure exactly the same floating-point behavior as
            # the parallel version with -ffast-math:
            # 1) Sum `new_row_sums` in a separate loop after the fact.
            # 2) If `QC_column` was specified, copy the row sums to a temporary
            #    buffer (`new_row_sums_contiguous`) before summing, to allow
            #    the sum to use SIMD.
            # 3) Launder `new_normalization_factor` through an intermediate
            #    variable declared as volatile, to force it to be calculated
            #    explicitly.
            new_row_sums.resize(num_cells)
            for i in range(num_cells):
                new_row_sum = 0
                inverse_size_factor = normalization_factor / row_sums[i]
                for j in range(<unsigned long long> indptr[i],
                               <unsigned long long> indptr[i + 1]):
                    normalized_data[j] = log1p(data[j] * inverse_size_factor)
                    new_row_sum += normalized_data[j]
                new_row_sums[i] = new_row_sum
            if not has_QC_column:
                for i in range(num_cells):
                    new_total_sum += new_row_sums[i]
            else:
                new_row_sums_contiguous.resize(num_QCed_cells)
                num_QCed_cells = 0
                for i in range(num_cells):
                    if QC_column[i]:
                        new_row_sums_contiguous[num_QCed_cells] = \
                            new_row_sums[i]
                        num_QCed_cells += 1
                for i in range(num_QCed_cells):
                    new_total_sum += new_row_sums_contiguous[i]
            new_normalization_factor_volatile = new_total_sum / num_QCed_cells
            new_normalization_factor = new_normalization_factor_volatile

            # Step 3b: calculate each cell's new inverse size factor and
            # multiply all normalized counts for that cell by it
            for i in range(num_cells):
                new_inverse_size_factor = \
                    new_normalization_factor / new_row_sums[i]
                for j in range(<unsigned long long> indptr[i],
                               <unsigned long long> indptr[i + 1]):
                    normalized_data[j] *= new_inverse_size_factor
    else:
        with nogil:
            # Step 1a and 1b: calculate row sums and the normalization factor
            # for the size factor calculation
            if method_number == 0:  # 'logCP10k'
                # Just calculate the row sums, and use a constant normalization
                # factor of 10,000
                with parallel(num_threads=num_threads):
                    thread_index = threadid()
                    row_range = \
                        get_thread_offset(indptr, thread_index, num_threads)
                    for i in range(row_range.first, row_range.second):
                        row_sum = 0
                        for j in range(<unsigned long long> indptr[i],
                                       <unsigned long long> indptr[i + 1]):
                            row_sum = row_sum + <unsigned long long> data[j]
                        row_sums[i] = row_sum
                normalization_factor = 10000
            else:
                # Same as the logCP10k version, but take the mean of the row
                # sums (across cells passing QC, if `QC_column` was specified)
                # as the size factor
                thread_total_sums.resize(num_threads)
                if not has_QC_column:
                    with parallel(num_threads=num_threads):
                        thread_index = threadid()
                        row_range = get_thread_offset(
                            indptr, thread_index, num_threads)
                        thread_total_sum = 0
                        for i in range(row_range.first, row_range.second):
                            row_sum = 0
                            for j in range(<unsigned long long> indptr[i],
                                           <unsigned long long> indptr[i + 1]):
                                row_sum = \
                                    row_sum + <unsigned long long> data[j]
                            row_sums[i] = row_sum
                            thread_total_sum = thread_total_sum + row_sum
                        thread_total_sums[thread_index] = thread_total_sum
                    for thread_index in range(num_threads):
                        total_sum += thread_total_sums[thread_index]
                    num_QCed_cells = num_cells
                else:
                    num_QCed_cells = 0
                    thread_nums_QCed_cells.resize(num_threads)
                    with parallel(num_threads=num_threads):
                        thread_index = threadid()
                        row_range = get_thread_offset(
                            indptr, thread_index, num_threads)
                        thread_total_sum = 0
                        thread_num_QCed_cells = 0
                        for i in range(row_range.first, row_range.second):
                            row_sum = 0
                            for j in range(<unsigned long long> indptr[i],
                                           <unsigned long long> indptr[i + 1]):
                                row_sum = \
                                    row_sum + <unsigned long long> data[j]
                            row_sums[i] = row_sum
                            if QC_column[i]:
                                thread_total_sum = thread_total_sum + row_sum
                                thread_num_QCed_cells = \
                                    thread_num_QCed_cells + 1
                        thread_total_sums[thread_index] = thread_total_sum
                        thread_nums_QCed_cells[thread_index] = \
                            thread_num_QCed_cells
                    for thread_index in range(num_threads):
                        total_sum += thread_total_sums[thread_index]
                        num_QCed_cells += thread_nums_QCed_cells[thread_index]
                normalization_factor = <float> total_sum / num_QCed_cells
            if method_number != 2:  # 'logCP10k' and 'log1pPF'
                # Step 1c and 2: calculate each cell's inverse size factor and
                # multiply all counts for that cell by it, then log1p-transform
                with parallel(num_threads=num_threads):
                    thread_index = threadid()
                    row_range = \
                        get_thread_offset(indptr, thread_index, num_threads)
                    for i in range(row_range.first, row_range.second):
                        inverse_size_factor = \
                            normalization_factor / row_sums[i]
                        for j in range(<unsigned long long> indptr[i],
                                       <unsigned long long> indptr[i + 1]):
                            normalized_data[j] = \
                                log1p(data[j] * inverse_size_factor)
            else:  # 'PFlog1pPF'
                # Step 1c, 2, and 3a: in addition to calculating each cell's
                # size factor and multiplying the counts by it, also calculate
                # the new row sums and total sum for a second round of
                # proportional fitting. To ensure exactly the same
                # floating-point behavior as the single-threaded version with
                # -ffast-math:
                # 1) Sum `new_row_sums` in a separate single-threaded loop
                #    after the fact.
                # 2) If `QC_column` was specified, copy the row sums to a
                #    temporary buffer (`new_row_sums_contiguous`) before
                #    summing, to allow the sum to use SIMD.
                # 3) Launder `new_normalization_factor` through an intermediate
                #    variable declared as volatile, to force it to be
                #    calculated explicitly.
                new_row_sums.resize(num_cells)
                with parallel(num_threads=num_threads):
                    thread_index = threadid()
                    row_range = \
                        get_thread_offset(indptr, thread_index, num_threads)
                    for i in range(row_range.first, row_range.second):
                        new_row_sum = 0
                        inverse_size_factor = \
                            normalization_factor / row_sums[i]
                        for j in range(<unsigned long long> indptr[i],
                                       <unsigned long long> indptr[i + 1]):
                            normalized_data[j] = \
                                log1p(data[j] * inverse_size_factor)
                            new_row_sum = new_row_sum + normalized_data[j]
                        new_row_sums[i] = new_row_sum
                if not has_QC_column:
                    for i in range(num_cells):
                        new_total_sum += new_row_sums[i]
                else:
                    new_row_sums_contiguous.resize(num_QCed_cells)
                    num_QCed_cells = 0
                    for i in range(num_cells):
                        if QC_column[i]:
                            new_row_sums_contiguous[num_QCed_cells] = \
                                new_row_sums[i]
                            num_QCed_cells += 1
                    for i in range(num_QCed_cells):
                        new_total_sum += new_row_sums_contiguous[i]
                new_normalization_factor_volatile = \
                    new_total_sum / num_QCed_cells
                new_normalization_factor = new_normalization_factor_volatile

                # Step 3b: calculate each cell's new inverse size factor and
                # multiply all normalized counts for that cell by it
                with parallel(num_threads=num_threads):
                    thread_index = threadid()
                    row_range = \
                        get_thread_offset(indptr, thread_index, num_threads)
                    for i in range(row_range.first, row_range.second):
                        new_inverse_size_factor = \
                            new_normalization_factor / new_row_sums[i]
                        for j in range(<unsigned long long> indptr[i],
                                       <unsigned long long> indptr[i + 1]):
                            normalized_data[j] *= new_inverse_size_factor


def normalize_csc(const numeric[::1] data,
                  const signed_integer[::1] indices,
                  const signed_integer[::1] indptr,
                  char[::1] QC_column,
                  float[::1] normalized_data,
                  unsigned long long[::1] row_sums,
                  const unsigned long long num_cells,
                  const unsigned method_number,
                  unsigned num_threads):

    cdef bint has_QC_column = QC_column.shape[0] != 0
    cdef unsigned i, thread_index
    cdef unsigned long long j, num_QCed_cells, start, end, chunk_size, \
        num_elements = data.shape[0], total_sum = 0
    cdef float normalization_factor, new_normalization_factor, \
        new_inverse_size_factor, new_total_sum = 0
    cdef volatile float inverse_size_factor, new_normalization_factor_volatile
    cdef vector[vector[unsigned long long]] thread_row_sums
    cdef vector[float] new_row_sums
    cdef uninitialized_vector[float] new_row_sums_contiguous

    num_threads = min(num_threads, min(num_cells, num_elements))
    if num_threads <= 1:
        # Step 1a: calculate row sums
        row_sums[:] = 0
        for j in range(num_elements):
            row_sums[indices[j]] += <unsigned long long> data[j]

        # Step 1b: calculate the normalization factor for the size factor
        # calculation
        if method_number == 0:  # 'logCP10k'
            normalization_factor = 10000
        else:
            # Take the mean of the row sums (across cells passing QC, if
            # `QC_column` was specified) as the size factor
            if not has_QC_column:
                for i in range(num_cells):
                    total_sum += row_sums[i]
                num_QCed_cells = num_cells
            else:
                num_QCed_cells = 0
                for i in range(num_cells):
                    if QC_column[i]:
                        total_sum += row_sums[i]
                        num_QCed_cells += 1
            normalization_factor = <float> total_sum / num_QCed_cells

        if method_number != 2:  # 'logCP10k' and 'log1pPF'
            # Step 1c and 2: multiply each count by its cell's inverse size
            # factor, then log1p-transform. Declare `inverse_size_factor` as
            # volatile to force it to be calculated explicitly.
            for j in range(num_elements):
                inverse_size_factor = \
                    normalization_factor / row_sums[indices[j]]
                normalized_data[j] = log1p(data[j] * inverse_size_factor)
        else:  # 'PFlog1pPF'
            # Step 1c, 2, and 3a: in addition to calculating each cell's size
            # factor and multiplying the counts by it, also calculate the new
            # row sums and total sum for a second round of proportional
            # fitting. Launder `new_normalization_factor` through an
            # intermediate variable declared as volatile, to force it to be
            # calculated explicitly and thereby ensure consistent
            # floating-point behavior under -ffast-math between the
            # single-threaded and parallel versions.
            new_row_sums.resize(num_cells)
            for j in range(num_elements):
                inverse_size_factor = \
                    normalization_factor / row_sums[indices[j]]
                normalized_data[j] = log1p(data[j] * inverse_size_factor)
                new_row_sums[indices[j]] += normalized_data[j]
            if not has_QC_column:
                for i in range(num_cells):
                    new_total_sum += new_row_sums[i]
            else:
                new_row_sums_contiguous.resize(num_QCed_cells)
                num_QCed_cells = 0
                for i in range(num_cells):
                    if QC_column[i]:
                        new_row_sums_contiguous[num_QCed_cells] = \
                            new_row_sums[i]
                        num_QCed_cells += 1
                for i in range(num_QCed_cells):
                    new_total_sum += new_row_sums_contiguous[i]
            new_normalization_factor_volatile = new_total_sum / num_QCed_cells
            new_normalization_factor = new_normalization_factor_volatile

            # Step 3b: calculate each cell's new inverse size factor and
            # multiply all normalized counts for that cell by it
            for j in range(num_elements):
                new_inverse_size_factor = \
                    new_normalization_factor / new_row_sums[indices[j]]
                normalized_data[j] *= new_inverse_size_factor
    else:
        with nogil:
            # Step 1a: calculate row sums. Store row sums for each thread in a
            # temporary buffer, then aggregate at the end. As an optimization,
            # put the row sums for the last thread
            # (`thread_index == num_threads - 1`) directly into the final
            # `row_sums` vector.
            thread_row_sums.resize(num_threads - 1)
            chunk_size = (num_elements + num_threads - 1) / num_threads
            with parallel(num_threads=num_threads):
                thread_index = threadid()
                start = thread_index * chunk_size
                if thread_index == num_threads - 1:
                    end = num_elements
                    for j in range(start, end):
                        row_sums[indices[j]] += <unsigned long long> data[j]
                else:
                    thread_row_sums[thread_index].resize(num_cells)
                    end = min(start + chunk_size, num_elements)
                    for j in range(start, end):
                        thread_row_sums[thread_index][indices[j]] += \
                            <unsigned long long> data[j]
            for thread_index in range(num_threads - 1):
                for i in range(num_cells):
                    row_sums[i] += thread_row_sums[thread_index][i]

            # Step 1b: calculate the normalization factor for the size factor
            # calculation
            if method_number == 0:  # 'logCP10k'
                normalization_factor = 10000
            else:
                # Take the mean of the row sums (across cells passing QC, if
                # `QC_column` was specified) as the size factor
                if not has_QC_column:
                    for i in prange(num_cells, num_threads=num_threads):
                        total_sum += row_sums[i]
                    num_QCed_cells = num_cells
                else:
                    num_QCed_cells = 0
                    for i in prange(num_cells, num_threads=num_threads):
                        if QC_column[i]:
                            total_sum += row_sums[i]
                            num_QCed_cells += 1
                normalization_factor = <float> total_sum / num_QCed_cells

            # Step 1c and 2: multiply each count by its cell's inverse size
            # factor, then log1p-transform
            for j in prange(num_elements, num_threads=num_threads):
                inverse_size_factor = \
                    normalization_factor / row_sums[indices[j]]
                normalized_data[j] = log1p(data[j] * inverse_size_factor)

            if method_number == 2:  # 'PFlog1pPF'
                # Step 3a: calculate the new row sums and total sum for a
                # second round of proportional fitting. This must be done
                # single-threaded to maintain a consistent order of operations
                # and avoid differences due to floating-point error between the
                # single-threaded and parallel versions. Launder
                # `new_normalization_factor` through an intermediate variable
                # declared as volatile, to force it to be calculated explicitly
                # and thereby ensure consistent floating-point behavior under
                # -ffast-math between the single-threaded and parallel
                # versions.
                new_row_sums.resize(num_cells)
                for j in range(num_elements):
                    new_row_sums[indices[j]] += normalized_data[j]
                if not has_QC_column:
                    for i in range(num_cells):
                        new_total_sum += new_row_sums[i]
                else:
                    new_row_sums_contiguous.resize(num_QCed_cells)
                    num_QCed_cells = 0
                    for i in range(num_cells):
                        if QC_column[i]:
                            new_row_sums_contiguous[num_QCed_cells] = \
                                new_row_sums[i]
                            num_QCed_cells += 1
                    for i in range(num_QCed_cells):
                        new_total_sum += new_row_sums_contiguous[i]
                new_normalization_factor_volatile = \
                    new_total_sum / num_QCed_cells
                new_normalization_factor = new_normalization_factor_volatile

                # Step 3b: calculate each cell's new inverse size factor and
                # multiply all normalized counts for that cell by it
                for j in prange(num_elements, num_threads=num_threads):
                    new_inverse_size_factor = \
                        new_normalization_factor / new_row_sums[indices[j]]
                    normalized_data[j] *= new_inverse_size_factor