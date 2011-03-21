#!/usr/bin/env python
import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
fig = plt.figure()
ax = fig.add_subplot(111, projection='3d')

a = np.loadtxt('at_x')
for i in range(a.shape[1]/3):
    ax.plot(np.mod(a[:,3*i],20.),np.mod(a[:,1+3*i],20.),np.mod(a[:,2+3*i],20.))
    ax.plot(np.mod(a[-2:,3*i],20.),np.mod(a[-2:,1+3*i],20.),np.mod(a[-2:,2+3*i],20.),ls='',marker='o')

ax.set_xlim3d(0,24)
ax.set_ylim3d(0,24)
ax.set_zlim3d(0,24)

plt.show()