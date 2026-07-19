# Functionality for loading from unchunked, uncompressed HDF5 files

import threading
cimport numpy as np
np.import_array()
from cython.parallel cimport parallel, threadid
from libc.string cimport memcpy
from libcpp.algorithm cimport sort
from libcpp.vector cimport vector
from signal import set_wakeup_fd
from socket import socketpair
from .cyutils cimport atomic_or, recv, uninitialized_vector


cdef extern from * nogil:
    """
    #if defined(_WIN32)
        #ifndef WIN32_LEAN_AND_MEAN
        #define WIN32_LEAN_AND_MEAN
        #endif
        #ifndef NOMINMAX
        #define NOMINMAX
        #endif
        #include <windows.h>
        #include <io.h>

        // Thread-safe pread equivalent for Windows using native Win32 API
        static inline long long cython_pread(int fd, void *buf, size_t count,
                                             long long offset) {
            HANDLE h = (HANDLE)_get_osfhandle(fd);
            if (h == INVALID_HANDLE_VALUE) {
                errno = EBADF;
                return -1;
            }

            OVERLAPPED o = {0};
            o.Offset = (DWORD)(offset & 0xFFFFFFFF);
            o.OffsetHigh = (DWORD)(offset >> 32);

            DWORD bytesRead = 0;
            if (!ReadFile(h, buf, (DWORD)count, &bytesRead, &o)) {
                if (GetLastError() == ERROR_HANDLE_EOF) {
                    return 0; // End of file reached gracefully
                }
                return -1; // Actual read error
            }
            return (long long)bytesRead;
        }
        #define CYTHON_PREAD cython_pread
        static inline void sleep_ms(int ms) {
            Sleep(ms);
        }
    #else
        #include <unistd.h>
        #include <time.h>

        #define CYTHON_PREAD pread
        static inline void sleep_ms(int ms) {
            usleep(ms * 1000);
        }

    #endif
    """
    long long pread "CYTHON_PREAD"(int fd, void *buf, size_t count,
                                   long long offset) noexcept
    void sleep_ms(int ms) noexcept nogil


cdef extern from "<errno.h>" nogil:
    int errno
    int EINTR
    int EAGAIN
    int EIO


cdef extern from "<atomic>" namespace "std" nogil:
    cdef cppclass atomic_int "std::atomic<int>":
        atomic_int()
        void store(int)
        int load()
        int exchange(int)


cdef extern from * nogil:
    """
    struct AddressCompare {
        const unsigned long long* data;
        AddressCompare() noexcept {}
        AddressCompare(const unsigned long long* d) noexcept : data(d) {}
        bool operator()(unsigned a, unsigned b) const noexcept {
            return data[a] < data[b];
        }
    };
    """
    cdef cppclass AddressCompare:
        AddressCompare(const unsigned long long*) noexcept
        bint operator()(unsigned, unsigned) noexcept


cdef inline void argsort_addresses(
        const unsigned long long* addresses, unsigned* indices,
        const unsigned n) noexcept nogil:
    cdef unsigned i
    for i in range(n):
        indices[i] = i
    sort(indices, indices + n, AddressCompare(addresses))


cdef inline void pread_all(int fd,
                           char *buf,
                           unsigned long long size,
                           unsigned long long offset,
                           atomic_int& error,
                           bint& interrupted,
                           int read_fd,
                           char* signal_byte) noexcept nogil:
    cdef unsigned long long chunk_size, total = 0
    cdef long long n
    cdef unsigned eagain_retries = 0, eio_retries = 0

    while total < size:
        chunk_size = size - total
        if chunk_size > 33_554_432:  # 32 MB chunks, to allow interrupt checks
            chunk_size = 33_554_432
        n = pread(fd, buf + total, chunk_size, offset + total)
        if n < 0:
            if errno == EINTR:
                # Interrupted by signal. No delay, instant retry.
                continue
            elif errno == EAGAIN:
                # Network queue full. Small backoff, many retries.
                eagain_retries += 1
                if eagain_retries > 50:
                    error.exchange(errno)
                    return
                sleep_ms(1 + eagain_retries)  # 2ms, 3ms, 4ms...
                continue
            elif errno == EIO:
                # Transient Lustre OST disconnect or lock revocation.
                # Heavier exponential backoff, fewer retries.
                eio_retries += 1
                if eio_retries > 6:
                    error.exchange(errno)
                    return
                sleep_ms(10 * (1 << eio_retries))  # 20ms, 40ms, 80ms, 160ms...
                continue
            else:
                # Fatal OS/alignment/memory error (EBADF, EFAULT, EINVAL, etc.)
                # Fail instantly.
                error.exchange(errno)
                return
        elif n == 0:
            # Reached true EOF before expected size (truncated/corrupted file)
            error.exchange(-1)
            return
        total += n
        if recv(read_fd, signal_byte, 1, 0) > 0:
            atomic_or(interrupted, True)
        if interrupted:
            return


def read_all_datasets(
        const int fd,
        list large_fixed_arrays,
        unsigned long long[::1] large_fixed_file_offsets,
        unsigned long long[::1] chunk_file_offsets,
        unsigned long long[::1] chunk_byte_sizes,
        unsigned long long[::1] chunk_destinations,
        unsigned long long[::1] chunk_thread_boundaries,
        unsigned long long[::1] vlen_file_offsets,
        unsigned long long[::1] vlen_num_strings,
        const unsigned length_size,
        const unsigned offset_size,
        const unsigned num_threads):

    cdef unsigned dataset_index, thread_index, collection_start, \
        collection_end, collection_index, object_index, vlen_index, \
        small_start, small_end, \
        num_large_fixed = large_fixed_file_offsets.shape[0], \
        num_vlen_datasets = vlen_file_offsets.shape[0], \
        max_object_index = 0
    cdef unsigned long long byte_start, byte_end, string_start, string_end, \
        num_strings, num_collections, string_index, original_index, position, \
        object_size, padded_size, lookup_stride, task_index, i, total, \
        address_val, dim, length, ref_size = 8 + offset_size, \
        header_size = 8 + length_size
    cdef unsigned short object_index16
    cdef int read_fd, old_fd
    cdef char signal_byte
    cdef np.ndarray array, output_offsets, output_data
    cdef unsigned long long* addresses_data
    cdef unsigned* sorted_order_data

    cdef uninitialized_vector[char*] large_fixed_destinations
    cdef uninitialized_vector[long long] large_fixed_byte_counts
    cdef uninitialized_vector[unsigned long long] sorted_addresses
    cdef uninitialized_vector[unsigned] large_vlen_indices, small_vlen_indices
    cdef vector[unsigned long long] vlen_num_collections, \
        vlen_collection_buffer_totals, object_offset_lookup_buffer, \
        object_length_lookup_buffer
    cdef vector[long long*] vlen_output_offsets
    cdef vector[unsigned char*] vlen_output_data
    cdef vector[uninitialized_vector[unsigned char]] vlen_raw_references, \
        vlen_collection_buffers
    cdef vector[uninitialized_vector[unsigned long long]] vlen_addresses, \
        vlen_unique_addresses, vlen_group_boundaries, vlen_collection_sizes, \
        vlen_collection_offsets, vlen_string_offsets
    cdef vector[uninitialized_vector[unsigned]] vlen_object_indices, \
        vlen_sorted_orders
    cdef unsigned long long[::1] object_offset_lookup, object_length_lookup
    cdef list vlen_offsets_out, vlen_data_out
    cdef bint interrupted = False, \
        main_thread = threading.current_thread() is threading.main_thread()
    cdef atomic_int error
    error.store(0)

    # Extract large fixed-width array metadata
    large_fixed_destinations.resize(num_large_fixed)
    large_fixed_byte_counts.resize(num_large_fixed)
    for dataset_index in range(num_large_fixed):
        array = large_fixed_arrays[dataset_index]
        large_fixed_destinations[dataset_index] = \
            <char*> np.PyArray_DATA(array)
        large_fixed_byte_counts[dataset_index] = array.nbytes

    # Allocate outer vectors for per-dataset vlen data, and separate vlen
    # datasets into large (>= 10k strings, read via per-thread slices) and
    # small (distributed contiguously among threads)
    vlen_string_offsets.resize(num_vlen_datasets)
    vlen_collection_buffers.resize(num_vlen_datasets)
    vlen_unique_addresses.resize(num_vlen_datasets)
    vlen_group_boundaries.resize(num_vlen_datasets)
    vlen_collection_sizes.resize(num_vlen_datasets)
    vlen_collection_offsets.resize(num_vlen_datasets)
    vlen_collection_buffer_totals.resize(num_vlen_datasets)
    vlen_num_collections.resize(num_vlen_datasets)
    vlen_sorted_orders.resize(num_vlen_datasets)
    vlen_object_indices.resize(num_vlen_datasets)
    vlen_raw_references.resize(num_vlen_datasets)
    vlen_addresses.resize(num_vlen_datasets)
    for dataset_index in range(num_vlen_datasets):
        num_strings = vlen_num_strings[dataset_index]
        if num_strings == 0:
            continue
        vlen_raw_references[dataset_index].resize(
            num_strings * ref_size)
        vlen_addresses[dataset_index].resize(num_strings)
        vlen_object_indices[dataset_index].resize(num_strings)
        vlen_sorted_orders[dataset_index].resize(num_strings)
        if num_strings >= 10000:
            large_vlen_indices.push_back(dataset_index)
        else:
            small_vlen_indices.push_back(dataset_index)

    r, w = socketpair()
    r.setblocking(False)
    w.setblocking(False)
    read_fd = r.fileno()
    if main_thread:
        old_fd = set_wakeup_fd(w.fileno())
    try:
        # First parallel region: pread all fixed-width datasets and vlen
        # reference arrays, then parse vlen references into flat addresses and
        # object_indices arrays
        with nogil, parallel(num_threads=num_threads):
            thread_index = threadid()

            # Large fixed-width datasets: each thread reads its 1 / num_threads
            # fraction of every dataset, for NUMA-awareness
            for dataset_index in range(num_large_fixed):
                byte_start = thread_index * \
                    large_fixed_byte_counts[dataset_index] / num_threads
                byte_end = (thread_index + 1) * \
                    large_fixed_byte_counts[dataset_index] / num_threads
                if byte_end > byte_start:
                    pread_all(
                        fd,
                        large_fixed_destinations[dataset_index] + byte_start,
                        byte_end - byte_start,
                        large_fixed_file_offsets[dataset_index] + byte_start,
                        error, interrupted, read_fd, &signal_byte)
                if interrupted or error.load():
                    break

            # Small fixed-width datasets: specific threads read specific
            # pre-assigned chunks from the bin-packing
            if not (interrupted or error.load()):
                for task_index in range(
                        chunk_thread_boundaries[thread_index],
                        chunk_thread_boundaries[thread_index + 1]):
                    pread_all(fd, <char*> chunk_destinations[task_index],
                              chunk_byte_sizes[task_index],
                              chunk_file_offsets[task_index],
                              error, interrupted, read_fd, &signal_byte)
                    if interrupted or error.load():
                        break

            # Large vlen reference arrays: every thread reads and parses its
            # 1 / num_threads fraction of every large vlen dataset
            if not (interrupted or error.load()):
                for vlen_index in range(large_vlen_indices.size()):
                    dataset_index = large_vlen_indices[vlen_index]
                    num_strings = vlen_num_strings[dataset_index]
                    string_start = thread_index * num_strings / num_threads
                    string_end = (thread_index + 1) * num_strings / num_threads
                    pread_all(
                        fd,
                        <char*> vlen_raw_references[dataset_index].data()
                            + string_start * ref_size,
                        (string_end - string_start) * ref_size,
                        vlen_file_offsets[dataset_index]
                            + string_start * ref_size,
                        error, interrupted, read_fd, &signal_byte)
                    if interrupted or error.load():
                        break
                    for i in range(string_start, string_end):
                        vlen_addresses[dataset_index][i] = 0
                        memcpy(&vlen_addresses[dataset_index][i],
                               vlen_raw_references[dataset_index].data()
                                   + i * ref_size + 4,
                               offset_size)
                        memcpy(&vlen_object_indices[dataset_index][i],
                               vlen_raw_references[dataset_index].data()
                                   + i * ref_size + 4 + offset_size,
                               4)

            # Small vlen reference arrays: distributed contiguously among
            # threads, where each thread reads and parses entire datasets
            if not (interrupted or error.load()):
                small_start = thread_index * small_vlen_indices.size() \
                    / num_threads
                small_end = (thread_index + 1) * small_vlen_indices.size() \
                    / num_threads
                for vlen_index in range(small_start, small_end):
                    dataset_index = small_vlen_indices[vlen_index]
                    num_strings = vlen_num_strings[dataset_index]
                    pread_all(
                        fd,
                        <char*> vlen_raw_references[dataset_index].data(),
                        num_strings * ref_size,
                        vlen_file_offsets[dataset_index],
                        error, interrupted, read_fd, &signal_byte)
                    if interrupted or error.load():
                        break
                    for i in range(num_strings):
                        vlen_addresses[dataset_index][i] = 0
                        memcpy(&vlen_addresses[dataset_index][i],
                               vlen_raw_references[dataset_index].data()
                                   + i * ref_size + 4,
                               offset_size)
                        memcpy(&vlen_object_indices[dataset_index][i],
                               vlen_raw_references[dataset_index].data()
                                   + i * ref_size + 4 + offset_size,
                               4)

        if interrupted:
            raise KeyboardInterrupt
        if error.load():
            if error.load() == -1:
                raise EOFError('pread() reached unexpected EOF')
            else:
                import os
                raise OSError(f'pread() failed: {os.strerror(error.load())}')

        # Free raw references and compute `max_object_index`
        for dataset_index in range(num_vlen_datasets):
            vlen_raw_references[dataset_index].clear()
            num_strings = vlen_num_strings[dataset_index]
            for i in range(num_strings):
                if vlen_object_indices[dataset_index][i] > max_object_index:
                    max_object_index = vlen_object_indices[dataset_index][i]

        # For each vlen dataset, argsort by collection address, gather
        # addresses into sort order (in parallel for large datasets), and find
        # unique addresses and group boundaries
        for dataset_index in range(num_vlen_datasets):
            num_strings = vlen_num_strings[dataset_index]
            if num_strings == 0:
                continue
            addresses_data = vlen_addresses[dataset_index].data()
            sorted_order_data = vlen_sorted_orders[dataset_index].data()

            argsort_addresses(addresses_data, sorted_order_data,
                              <unsigned> num_strings)

            # Gather addresses into sort order so the boundary scan is
            # sequential; do this in parallel for large datasets
            sorted_addresses.resize(num_strings)
            if num_strings >= 10000:
                with nogil, parallel(num_threads=num_threads):
                    thread_index = threadid()
                    string_start = thread_index * num_strings / num_threads
                    string_end = (thread_index + 1) * num_strings / num_threads
                    for i in range(string_start, string_end):
                        sorted_addresses[i] = \
                            addresses_data[sorted_order_data[i]]
            else:
                for i in range(num_strings):
                    sorted_addresses[i] = addresses_data[sorted_order_data[i]]
            vlen_addresses[dataset_index].clear()

            # Find unique addresses and group boundaries
            vlen_unique_addresses[dataset_index].push_back(
                sorted_addresses[0])
            vlen_group_boundaries[dataset_index].push_back(0)
            for i in range(1, num_strings):
                if sorted_addresses[i] != sorted_addresses[i - 1]:
                    vlen_unique_addresses[dataset_index].push_back(
                        sorted_addresses[i])
                    vlen_group_boundaries[dataset_index].push_back(i)
            vlen_group_boundaries[dataset_index].push_back(num_strings)

            num_collections = \
                vlen_unique_addresses[dataset_index].size()
            vlen_num_collections[dataset_index] = num_collections
            vlen_collection_sizes[dataset_index].resize(num_collections)
            vlen_collection_offsets[dataset_index].resize(num_collections)

        # Second parallel region: read collection headers
        with nogil, parallel(num_threads=num_threads):
            thread_index = threadid()
            for dataset_index in range(num_vlen_datasets):
                num_collections = vlen_num_collections[dataset_index]
                if num_collections == 0:
                    continue
                collection_start = \
                    thread_index * num_collections / num_threads
                collection_end = \
                    (thread_index + 1) * num_collections / num_threads
                for collection_index in range(
                        collection_start, collection_end):
                    address_val = vlen_unique_addresses[
                        dataset_index][collection_index]
                    vlen_collection_sizes[
                        dataset_index][collection_index] = 0
                    if address_val != 0:
                        pread_all(
                            fd,
                            <char*> &vlen_collection_sizes[
                                dataset_index][collection_index],
                            length_size, address_val + 8,
                            error, interrupted, read_fd, &signal_byte)
                    if interrupted or error.load():
                        break
                if interrupted or error.load():
                    break

        if interrupted:
            raise KeyboardInterrupt
        if error.load():
            if error.load() == -1:
                raise EOFError('pread() reached unexpected EOF')
            else:
                import os
                raise OSError(f'pread() failed: {os.strerror(error.load())}')

        # Compute collection buffer offsets and totals from sizes
        for dataset_index in range(num_vlen_datasets):
            num_collections = vlen_num_collections[dataset_index]
            total = 0
            for i in range(num_collections):
                vlen_collection_offsets[dataset_index][i] = total
                total = total + vlen_collection_sizes[dataset_index][i]
            vlen_collection_buffer_totals[dataset_index] = total

        # Allocate dynamic arrays and output variables
        vlen_offsets_out = []
        vlen_data_out = []
        for dataset_index in range(num_vlen_datasets):
            num_strings = vlen_num_strings[dataset_index]

            dim = num_strings + 1
            # output_offsets = np.zeros(dim, dtype=int)
            output_offsets = \
                np.PyArray_ZEROS(1, <np.npy_intp*> &dim, np.NPY_LONGLONG, 0)

            dim = vlen_collection_buffer_totals[dataset_index]
            # output_data = np.empty(dim, dtype=np.uint8)
            output_data = \
                np.PyArray_EMPTY(1, <np.npy_intp*> &dim, np.NPY_UINT8, 0)

            vlen_offsets_out.append(output_offsets)
            vlen_data_out.append(output_data)
            vlen_output_offsets.push_back(
                <long long*> np.PyArray_DATA(output_offsets))
            vlen_output_data.push_back(
                <unsigned char*> np.PyArray_DATA(output_data))
            vlen_string_offsets[dataset_index].resize(num_strings)
            vlen_collection_buffers[dataset_index].resize(dim)

        lookup_stride = max_object_index + 1
        object_offset_lookup_buffer.resize(num_threads * lookup_stride)
        object_offset_lookup = \
            <unsigned long long[:num_threads * lookup_stride]> \
            object_offset_lookup_buffer.data()
        object_length_lookup_buffer.resize(num_threads * lookup_stride)
        object_length_lookup = \
            <unsigned long long[:num_threads * lookup_stride]> \
            object_length_lookup_buffer.data()

        # Third parallel region: pread collection bodies, walk heap
        # objects, and record per-string info
        with nogil, parallel(num_threads=num_threads):
            thread_index = threadid()

            for dataset_index in range(num_vlen_datasets):
                num_collections = vlen_num_collections[dataset_index]
                collection_start = \
                    thread_index * num_collections / num_threads
                collection_end = \
                    (thread_index + 1) * num_collections / num_threads
                for collection_index in range(
                        collection_start, collection_end):
                    if vlen_collection_sizes[
                            dataset_index][collection_index] <= 0:
                        continue
                    pread_all(
                        fd,
                        <char*> (vlen_collection_buffers[dataset_index].data()
                            + vlen_collection_offsets[
                                dataset_index][collection_index]),
                        vlen_collection_sizes[
                            dataset_index][collection_index],
                        vlen_unique_addresses[
                            dataset_index][collection_index],
                        error, interrupted, read_fd, &signal_byte)
                    if interrupted or error.load():
                        break

                    # Walk heap objects to build the per-thread lookup table
                    position = vlen_collection_offsets[
                        dataset_index][collection_index] + header_size
                    while position + header_size <= \
                            vlen_collection_offsets[
                                dataset_index][collection_index] + \
                            vlen_collection_sizes[
                                dataset_index][collection_index]:
                        object_index16 = 0  # force thread-private
                        memcpy(&object_index16,
                               vlen_collection_buffers[dataset_index].data() +
                                   position,
                               sizeof(unsigned short))
                        object_index = object_index16
                        object_size = 0
                        memcpy(&object_size,
                               vlen_collection_buffers[dataset_index].data() +
                                   position + 8,
                               length_size)
                        if object_index == 0 or \
                                position + header_size + object_size > \
                                vlen_collection_offsets[
                                    dataset_index][collection_index] + \
                                vlen_collection_sizes[
                                    dataset_index][collection_index]:
                            break  # end of collection
                        if object_index <= max_object_index:
                            object_offset_lookup[thread_index * lookup_stride +
                                                 object_index] = \
                                position + header_size
                            object_length_lookup[thread_index * lookup_stride +
                                                 object_index] = \
                                object_size - 1 if object_size > 0 and \
                                vlen_collection_buffers[dataset_index].data()[
                                    position + header_size +
                                    object_size - 1] == 0 else object_size
                        padded_size = (object_size + 7) & ~7ULL
                        position = position + header_size + padded_size

                    # Record per-string info
                    for string_index in range(
                            vlen_group_boundaries[
                                dataset_index][collection_index],
                            vlen_group_boundaries[
                                dataset_index][collection_index + 1]):
                        original_index = \
                            vlen_sorted_orders[
                                dataset_index][string_index]
                        object_index = \
                            vlen_object_indices[
                                dataset_index][original_index]
                        vlen_output_offsets[
                                dataset_index][original_index + 1] = \
                            object_length_lookup[
                                thread_index * lookup_stride + object_index]
                        vlen_string_offsets[dataset_index][original_index] = \
                            object_offset_lookup[
                                thread_index * lookup_stride + object_index]
                if interrupted or error.load():
                    break

        if interrupted:
            raise KeyboardInterrupt
        if error.load():
            if error.load() == -1:
                raise EOFError('pread() reached unexpected EOF')
            else:
                import os
                raise OSError(f'pread() failed: {os.strerror(error.load())}')

        # Cumsum (single-threaded)
        for dataset_index in range(num_vlen_datasets):
            num_strings = vlen_num_strings[dataset_index]
            for i in range(1, num_strings):
                vlen_output_offsets[dataset_index][i + 1] += \
                    vlen_output_offsets[dataset_index][i]

        # Fourth parallel region: copy string bytes to output
        if num_vlen_datasets > 0:
            with nogil, parallel(num_threads=num_threads):
                thread_index = threadid()
                for dataset_index in range(num_vlen_datasets):
                    num_strings = vlen_num_strings[dataset_index]
                    string_start = thread_index * num_strings / num_threads
                    string_end = (thread_index + 1) * num_strings / num_threads
                    for i in range(string_start, string_end):
                        length = vlen_output_offsets[dataset_index][i + 1] - \
                                 vlen_output_offsets[dataset_index][i]
                        if length > 0:
                            memcpy(vlen_output_data[dataset_index] +
                                       vlen_output_offsets[dataset_index][i],
                                   vlen_collection_buffers[
                                       dataset_index].data() +
                                       vlen_string_offsets[dataset_index][i],
                                   length)

    finally:
        if main_thread:
            set_wakeup_fd(old_fd)
        r.close()
        w.close()

    return vlen_offsets_out, vlen_data_out