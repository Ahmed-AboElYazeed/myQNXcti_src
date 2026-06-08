import numpy as np

# create two dimensional array
a = np.array([[1, 2, 3],
              [4, 5, 6]])

print(f'a\'s shape: {a.shape}\n')

# create one dimensional array from list
b = np.array([1, 2, 3, 4, 5, 6])

print(f'b: {b}\n')

# access first element of array
print(f'b[0]: {b[0]}\n')

#modify the first element of the array
b[0] = 10

print(f'updated b: {b}\n')

# slicing an array
c = b[3:]

print(f'c (slice of b): {c}\n')

# update b after slicing
c[0] = 40

print(f'updated b: {b}\n')

# declare a new 3 x 4 array
d = np.array([[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]])

print(f'd:\n{d}\n')

# access an element in the 2D array
print(f'd[1, 3]: {d[1, 3]}\n')

