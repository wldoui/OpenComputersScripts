-- ==================================================================
-- lib/matrix3.lua
-- Rotation helpers for the 3D engine. We only need rotation (the
-- scene is camera-centric with a simple offset for translation), so
-- this is a set of 3x3 rotation builders + apply, not a full 4x4
-- homogeneous matrix stack. Keeps it cheap enough for OpenComputers.
-- ==================================================================

local Vector3 = require("vector3")

local Matrix3 = {}

-- Builds a combined rotation matrix (Yaw * Pitch * Roll), each as a
-- flat 3x3 array {m11,m12,m13, m21,m22,m23, m31,m32,m33}.
function Matrix3.fromEuler(pitchRad, yawRad, rollRad)
  local cp, sp = math.cos(pitchRad), math.sin(pitchRad)
  local cy, sy = math.cos(yawRad), math.sin(yawRad)
  local cr, sr = math.cos(rollRad), math.sin(rollRad)

  -- Rotation around X (pitch)
  local Rx = {
    1, 0, 0,
    0, cp, -sp,
    0, sp, cp
  }
  -- Rotation around Y (yaw)
  local Ry = {
    cy, 0, sy,
    0, 1, 0,
    -sy, 0, cy
  }
  -- Rotation around Z (roll)
  local Rz = {
    cr, -sr, 0,
    sr, cr, 0,
    0, 0, 1
  }

  return Matrix3.multiply(Matrix3.multiply(Ry, Rx), Rz)
end

function Matrix3.multiply(a, b)
  local r = {}
  for row = 0, 2 do
    for col = 0, 2 do
      local sum = 0
      for k = 0, 2 do
        sum = sum + a[row * 3 + k + 1] * b[k * 3 + col + 1]
      end
      r[row * 3 + col + 1] = sum
    end
  end
  return r
end

function Matrix3.apply(m, v)
  return Vector3.new(
    m[1] * v.x + m[2] * v.y + m[3] * v.z,
    m[4] * v.x + m[5] * v.y + m[6] * v.z,
    m[7] * v.x + m[8] * v.y + m[9] * v.z
  )
end

return Matrix3
