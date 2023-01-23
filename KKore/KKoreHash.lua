--
-- KahLua Kore - MD5 hashing and CRC checking.
--
-- MD5 converted from C code written by Colin Plumb in 1993. He claims
-- no copyright and the code is in the public domain, as is this Lua
-- implementation. The MD5 conversion done by Kean Johnston (Cruciformer).
-- See http://cvsweb.xfree86.org/cvsweb/cvs/lib/md5.c?rev=1.1.1.2 for the
-- original source. I modified the algorithm to not rely on memcpy() which
-- is problematic in Lua.
--
-- Quick CRC-32 calculation code provided by Allara on Curseforge
-- (http://forums.curseforge.com/showthread.php?t=15001). I also modified
-- that code to allow for a running calculation.
--

local KKOREHASH_MAJOR = "KKoreHash"
local KKOREHASH_MINOR = 4
local H, oldminor = LibStub:NewLibrary(KKOREHASH_MAJOR, KKOREHASH_MINOR)

if (not H) then
  return
end

H.debug_id = KKOREHASH_MAJOR

local K, KM = LibStub:GetLibrary("KKore")
assert (K, "KKoreHash requires KKore")
assert (tonumber(KM) >= 4, "KKoreHash requires KKore r4 or later")
K:RegisterExtension (H, KKOREHASH_MAJOR, KKOREHASH_MINOR)

local bor = bit.bor
local band = bit.band
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift
local bmod = bit.mod
local strchr = string.char
local strlen = string.len
local strbyte = string.byte
local strsub = string.sub
local strrep = string.rep
local strfmt = string.format
local tinsert = table.insert
local tremove = table.remove

local ff = 0xffffffff

local md5magic = {
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
}

local function F1(x, y, z)
  return bor(band(x, y),band(-x - 1, z))
end

local function F2(x, y, z)
  return bor(band(x, z),band(y, -z - 1))
end

local function F3(x, y, z)
  return bxor(x, bxor(y, z))
end

local function F4(x, y, z)
  return bxor(y, bor(x, -z - 1))
end

local function MSTEP(f, a, b, c, d, x, s, mv)
  a = band(a + f(b, c, d) + x + mv, ff)
  return bor(lshift(band(a, rshift(ff, s)), s),rshift(a, 32 - s)) + b
end

local function MD5xform(cbuf, ibuf)
  local a, b, c, d = unpack(cbuf, 0, 3)

  a = MSTEP(F1, a, b, c, d, ibuf[ 0],  7, md5magic[ 1])
  d = MSTEP(F1, d, a, b, c, ibuf[ 1], 12, md5magic[ 2])
  c = MSTEP(F1, c, d, a, b, ibuf[ 2], 17, md5magic[ 3])
  b = MSTEP(F1, b, c, d, a, ibuf[ 3], 22, md5magic[ 4])
  a = MSTEP(F1, a, b, c, d, ibuf[ 4],  7, md5magic[ 5])
  d = MSTEP(F1, d, a, b, c, ibuf[ 5], 12, md5magic[ 6])
  c = MSTEP(F1, c, d, a, b, ibuf[ 6], 17, md5magic[ 7])
  b = MSTEP(F1, b, c, d, a, ibuf[ 7], 22, md5magic[ 8])
  a = MSTEP(F1, a, b, c, d, ibuf[ 8],  7, md5magic[ 9])
  d = MSTEP(F1, d, a, b, c, ibuf[ 9], 12, md5magic[10])
  c = MSTEP(F1, c, d, a, b, ibuf[10], 17, md5magic[11])
  b = MSTEP(F1, b, c, d, a, ibuf[11], 22, md5magic[12])
  a = MSTEP(F1, a, b, c, d, ibuf[12],  7, md5magic[13])
  d = MSTEP(F1, d, a, b, c, ibuf[13], 12, md5magic[14])
  c = MSTEP(F1, c, d, a, b, ibuf[14], 17, md5magic[15])
  b = MSTEP(F1, b, c, d, a, ibuf[15], 22, md5magic[16])

  a = MSTEP(F2, a, b, c, d, ibuf[ 1],  5, md5magic[17])
  d = MSTEP(F2, d, a, b, c, ibuf[ 6],  9, md5magic[18])
  c = MSTEP(F2, c, d, a, b, ibuf[11], 14, md5magic[19])
  b = MSTEP(F2, b, c, d, a, ibuf[ 0], 20, md5magic[20])
  a = MSTEP(F2, a, b, c, d, ibuf[ 5],  5, md5magic[21])
  d = MSTEP(F2, d, a, b, c, ibuf[10],  9, md5magic[22])
  c = MSTEP(F2, c, d, a, b, ibuf[15], 14, md5magic[23])
  b = MSTEP(F2, b, c, d, a, ibuf[ 4], 20, md5magic[24])
  a = MSTEP(F2, a, b, c, d, ibuf[ 9],  5, md5magic[25])
  d = MSTEP(F2, d, a, b, c, ibuf[14],  9, md5magic[26])
  c = MSTEP(F2, c, d, a, b, ibuf[ 3], 14, md5magic[27])
  b = MSTEP(F2, b, c, d, a, ibuf[ 8], 20, md5magic[28])
  a = MSTEP(F2, a, b, c, d, ibuf[13],  5, md5magic[29])
  d = MSTEP(F2, d, a, b, c, ibuf[ 2],  9, md5magic[30])
  c = MSTEP(F2, c, d, a, b, ibuf[ 7], 14, md5magic[31])
  b = MSTEP(F2, b, c, d, a, ibuf[12], 20, md5magic[32])

  a = MSTEP(F3, a, b, c, d, ibuf[ 5],  4, md5magic[33])
  d = MSTEP(F3, d, a, b, c, ibuf[ 8], 11, md5magic[34])
  c = MSTEP(F3, c, d, a, b, ibuf[11], 16, md5magic[35])
  b = MSTEP(F3, b, c, d, a, ibuf[14], 23, md5magic[36])
  a = MSTEP(F3, a, b, c, d, ibuf[ 1],  4, md5magic[37])
  d = MSTEP(F3, d, a, b, c, ibuf[ 4], 11, md5magic[38])
  c = MSTEP(F3, c, d, a, b, ibuf[ 7], 16, md5magic[39])
  b = MSTEP(F3, b, c, d, a, ibuf[10], 23, md5magic[40])
  a = MSTEP(F3, a, b, c, d, ibuf[13],  4, md5magic[41])
  d = MSTEP(F3, d, a, b, c, ibuf[ 0], 11, md5magic[42])
  c = MSTEP(F3, c, d, a, b, ibuf[ 3], 16, md5magic[43])
  b = MSTEP(F3, b, c, d, a, ibuf[ 6], 23, md5magic[44])
  a = MSTEP(F3, a, b, c, d, ibuf[ 9],  4, md5magic[45])
  d = MSTEP(F3, d, a, b, c, ibuf[12], 11, md5magic[46])
  c = MSTEP(F3, c, d, a, b, ibuf[15], 16, md5magic[47])
  b = MSTEP(F3, b, c, d, a, ibuf[ 2], 23, md5magic[48])

  a = MSTEP(F4, a, b, c, d, ibuf[ 0],  6, md5magic[49])
  d = MSTEP(F4, d, a, b, c, ibuf[ 7], 10, md5magic[50])
  c = MSTEP(F4, c, d, a, b, ibuf[14], 15, md5magic[51])
  b = MSTEP(F4, b, c, d, a, ibuf[ 5], 21, md5magic[52])
  a = MSTEP(F4, a, b, c, d, ibuf[12],  6, md5magic[53])
  d = MSTEP(F4, d, a, b, c, ibuf[ 3], 10, md5magic[54])
  c = MSTEP(F4, c, d, a, b, ibuf[10], 15, md5magic[55])
  b = MSTEP(F4, b, c, d, a, ibuf[ 1], 21, md5magic[56])
  a = MSTEP(F4, a, b, c, d, ibuf[ 8],  6, md5magic[57])
  d = MSTEP(F4, d, a, b, c, ibuf[15], 10, md5magic[58])
  c = MSTEP(F4, c, d, a, b, ibuf[ 6], 15, md5magic[59])
  b = MSTEP(F4, b, c, d, a, ibuf[13], 21, md5magic[60])
  a = MSTEP(F4, a, b, c, d, ibuf[ 4],  6, md5magic[61])
  d = MSTEP(F4, d, a, b, c, ibuf[11], 10, md5magic[62])
  c = MSTEP(F4, c, d, a, b, ibuf[ 2], 15, md5magic[63])
  b = MSTEP(F4, b, c, d, a, ibuf[ 9], 21, md5magic[64])

  cbuf[0] = band(cbuf[0] + a, ff)
  cbuf[1] = band(cbuf[1] + b, ff)
  cbuf[2] = band(cbuf[2] + c, ff)
  cbuf[3] = band(cbuf[3] + d, ff)
end

function H:MD5Init()
  local ret = {buf = {}, bits = {}, inbuf = {}}
  ret.buf[0] = 0x67452301
  ret.buf[1] = 0xefcdab89
  ret.buf[2] = 0x98badcfe
  ret.buf[3] = 0x10325476
  ret.bits[0] = 0
  ret.bits[1] = 0
  return ret
end

function H:MD5Update(ctx, buf, len)
  local ibuf = {}
  local t, j, k, l

  if (not len) then
    len = strlen(buf)
  end

  t = band(rshift(ctx.bits[0], 3), 0x3f)

  if ((ctx.bits[0] + lshift(len, 3)) < ctx.bits[0]) then
    cts.bits[1] = ctx.bits[1] + 1
  end
  ctx.bits[0] = ctx.bits[0] + lshift(len, 3)
  ctx.bits[1] = ctx.bits[1] + rshift(len, 29)

  for l = 1, len do
    ctx.inbuf[t] = band(strbyte(buf, l, l), 0xff)
    t = t + 1
    if (t == 64) then
      k = 0
      for j = 0, 15 do
        ibuf[j] = band(band(lshift(ctx.inbuf[k+3], 24), ff) +
          band(lshift(ctx.inbuf[k+2], 16), ff) +
          band(lshift(ctx.inbuf[k+1], 8), ff) +
          band(ctx.inbuf[k], ff), ff)
          k = k + 4
      end
      MD5xform(ctx.buf, ibuf)
      t = 0
    end
  end
end

local md5pad = strchr(128) .. strrep(strchr(0), 63)

function H:MD5Final(ctx)
  local digest = {}
  local ibuf = {}
  local t, j, k, l, p

  ibuf[14] = band(ctx.bits[0], ff)
  ibuf[15] = band(ctx.bits[1], ff)

  t = band(rshift(ctx.bits[0], 3), 0x3f)
  if (t < 56) then
    p = 56 - t
  else
    p = 120 - t
  end
  H:MD5Update(ctx, md5pad, p)

  k = 0
  for j = 0, 13 do
    ibuf[j] = band(band(lshift(ctx.inbuf[k+3], 24), ff) +
      band(lshift(ctx.inbuf[k+2], 16), ff) +
      band(lshift(ctx.inbuf[k+1], 8), ff) +
      band(ctx.inbuf[k], ff), ff)
    k = k + 4
  end
  MD5xform(ctx.buf, ibuf)

  k = 0
  for j = 0, 3 do
    digest[k] = band(ctx.buf[j], 0xff)
    digest[k+1] = band(rshift(ctx.buf[j], 8), 0xff)
    digest[k+2] = band(rshift(ctx.buf[j], 16), 0xff)
    digest[k+3] = band(rshift(ctx.buf[j], 24), 0xff)
    k = k + 4
  end

  ctx.buf[0] = nil
  ctx.buf[1] = nil
  ctx.buf[2] = nil
  ctx.buf[3] = nil
  ctx.bits[0] = nil
  ctx.bits[1] = nil
  ctx.inbuf = nil
  ctx = nil

  return strfmt(strrep("%02x", 16), unpack(digest, 0, 15))
end

function H:MD5(s)
  local ctx = H:MD5Init()
  H:MD5Update(ctx, s)
  return H:MD5Final(ctx)
end

local crc_mod = {
  0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419,
  0x706AF48F, 0xE963A535, 0x9E6495A3, 0x0EDB8832, 0x79DCB8A4,
  0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07,
  0x90BF1D91, 0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
  0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7, 0x136C9856,
  0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9,
  0xFA0F3D63, 0x8D080DF5, 0x3B6E20C8, 0x4C69105E, 0xD56041E4,
  0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
  0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3,
  0x45DF5C75, 0xDCD60DCF, 0xABD13D59, 0x26D930AC, 0x51DE003A,
  0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599,
  0xB8BDA50F, 0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
  0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D, 0x76DC4190,
  0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F,
  0x9FBFE4A5, 0xE8B8D433, 0x7807C9A2, 0x0F00F934, 0x9609A88E,
  0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
  0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED,
  0x1B01A57B, 0x8208F4C1, 0xF50FC457, 0x65B0D9C6, 0x12B7E950,
  0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3,
  0xFBD44C65, 0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2,
  0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB, 0x4369E96A,
  0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5,
  0xAA0A4C5F, 0xDD0D7CC9, 0x5005713C, 0x270241AA, 0xBE0B1010,
  0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
  0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17,
  0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD, 0xEDB88320, 0x9ABFB3B6,
  0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615,
  0x73DC1683, 0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8,
  0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1, 0xF00F9344,
  0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB,
  0x196C3671, 0x6E6B06E7, 0xFED41B76, 0x89D32BE0, 0x10DA7A5A,
  0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
  0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1,
  0xA6BC5767, 0x3FB506DD, 0x48B2364B, 0xD80D2BDA, 0xAF0A1B4C,
  0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF,
  0x4669BE79, 0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
  0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F, 0xC5BA3BBE,
  0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31,
  0x2CD99E8B, 0x5BDEAE1D, 0x9B64C2B0, 0xEC63F226, 0x756AA39C,
  0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
  0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B,
  0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21, 0x86D3D2D4, 0xF1D4E242,
  0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1,
  0x18B74777, 0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C,
  0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45, 0xA00AE278,
  0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7,
  0x4969474D, 0x3E6E77DB, 0xAED16A4A, 0xD9D65ADC, 0x40DF0B66,
  0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
  0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605,
  0xCDD70693, 0x54DE5729, 0x23D967BF, 0xB3667A2E, 0xC4614AB8,
  0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B,
  0x2D02EF8D }
 
function H:CRC32(data, current_crc, finalise)
  local crc
  local l = strlen(data)
  local j

  if (c ~= nil) then
    crc = current_crc
  else
    crc = ff
  end

  for j = 1, l, 1 do
    crc = bxor(rshift(crc, 8), crc_mod[band(bxor(crc, strbyte(data, j)), 0xFF) + 1])
  end

  if (finalise == false) then
    return crc
  end

  return bxor(crc, ff)
end

