// Renders the Now Playing turntable's images with a small GPU path tracer.
// Usage: swiftc -O scripts/render-turntable.swift -o /tmp/rt && /tmp/rt Resources/Turntable [samples]
//
// The scene is built from signed distance functions in the same 1000 × 760
// space as TurntableGeometry (x right, y down, z towards the viewer) and lit by
// softboxes. Only run this to change how the turntable looks.
import AppKit
import ImageIO
import Metal
import UniformTypeIdentifiers

let shader = #"""
#include <metal_stdlib>
using namespace metal;

#define UA constant U &u, texture2d<float> tx
#define UU u, tx
struct U { uint w, h, mode, frame; float2 origin; float scale, armAngle, shear; uint noArm; };

// Geometry shared with TurntableGeometry.
constant float2 SP = float2(390, 380);     // spindle
constant float2 PV = float2(845, 168);     // arm pivot
constant float PLATTER = 346, RECORD = 326, LABEL = 132, LEADOUT = 156;
constant float HEAD = 0.308923;            // headshell offset
constant float REST = 0.0785398;

enum { DECK = 1, CHAMFER, WELL, RIM, MAT, VINYL, PAPER, BASE, RING, PIVOT, REST_ID, TUBE, WEIGHT, YOKE, SHELL, CART, SCREW, LIFT, LEDRING, FRONT, DIAL, PILLAR, LOGO };
constant float4 LOGO_AREA = float4(30, 668, 220, 60);   // x, y, width, height

static uint pcg(thread uint &s) { s = s * 747796405u + 2891336453u; uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u; return (w >> 22u) ^ w; }
static float rnd(thread uint &s) { return float(pcg(s)) * 2.3283064e-10f; }
static float hash(float2 p) { p = fract(p * float2(0.1031, 0.1030)); p += dot(p, p.yx + 33.33); return fract((p.x + p.y) * p.x); }
static float2 rot(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }

static float sdBox2(float2 p, float2 b, float r) { float2 q = abs(p) - b + r; return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - r; }
static float extrude(float d, float z, float lo, float hi, float round) {
    float2 w = float2(d, abs(z - (lo + hi) * 0.5f) - (hi - lo) * 0.5f) + round;
    return min(max(w.x, w.y), 0.0f) + length(max(w, 0.0f)) - round;
}
// 45° chamfer on the top edge.
static float extrudeChamfer(float d, float z, float lo, float hi, float c) {
    return max(max(d, abs(z - (lo + hi) * 0.5f) - (hi - lo) * 0.5f), (d + z - hi + c) * 0.70710678f);
}
static float capsule(float3 p, float3 a, float3 b, float r) { float3 pa = p - a, ba = b - a; return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0f, 1.0f)) - r; }
static void add(thread float2 &r, float d, int id) { if (d < r.x) r = float2(d, id); }

// Arm, in its own frame: pivot at the origin, pointing along +y.
static float2 mapArm(float3 p) {
    float2 r = float2(1e5, 0);
    const float Z = 54;
    float2 dir = float2(-sin(HEAD), cos(HEAD));
    float2 neck = float2(0, 520) - dir * 95;
    float bound = sdBox2(p.xy - float2(0, 190), float2(80, 360), 0);
    if (bound > 60) return float2(bound, 0);

    // Tube: straight, then a curve down into the headshell.
    float3 pts[11];
    pts[0] = float3(0, -90, Z); pts[1] = float3(0, 0, Z); pts[2] = float3(22, 290, Z - 6);
    float2 c0 = float2(22, 290), c1 = float2(29, 352), c2 = neck - dir * 40, c3 = neck + dir * 4;
    for (int i = 1; i <= 8; i++) {
        float t = float(i) / 8, u = 1 - t;
        float2 b = u*u*u*c0 + 3*u*u*t*c1 + 3*u*t*t*c2 + t*t*t*c3;
        pts[2 + i] = float3(b, mix(Z - 6, 42.0f, t));
    }
    float d = 1e5;
    for (int i = 0; i < 10; i++) d = min(d, capsule(p, pts[i], pts[i + 1], 6.6));
    add(r, d, TUBE);
    // Collars where the tube enters the bearing.
    { float3 q = p - float3(1.2, 46, Z); float a = length(q.xz) - 10; add(r, extrude(a, q.y, -9, 9, 2), WEIGHT); }

    // Counterweight with a knurled grip and a dial ring.
    {
        float3 q = p - float3(0, -106, Z - 2);
        float rad = length(q.xz), ang = atan2(q.x, q.z);
        float R = 34;
        if (q.y < 4 && q.y > -26) R += 0.55f * clamp(cos(ang * 90), -0.6f, 0.6f);
        if (abs(q.y - 8) < 1.6f) R -= 2.2f;
        if (abs(q.y + 29) < 1.2f) R -= 1.6f;
        add(r, extrude(rad - R, q.y, -38, 32, 3.5) * 0.8f, WEIGHT);
        add(r, extrude(rad - 10, q.y, -42, -30, 1.5), YOKE);
    }
    // Bearing: gimbal ring with its side screws, and the cap on top.
    {
        float2 c = p.xy;
        float ring = abs(length(c) - 33) - 5;
        add(r, extrude(ring, p.z, 40, 62, 2.2), YOKE);
        for (int s = -1; s <= 1; s += 2) {
            float3 q = p - float3(s * 40, 0, 51);
            add(r, extrude(length(q.yz) - 7, q.x, -5, 5, 1.5), SCREW);
        }
        add(r, extrude(sdBox2(c, float2(13, 22), 5), p.z, 44, 64, 2.5), PIVOT);
        float cap = extrude(length(c) - 9, p.z, 60, 68, 2);
        add(r, cap, SCREW);
    }
    // Headshell, cartridge, screws, finger lift.
    {
        float3 q = p - float3(neck, 0);
        q.xy = rot(q.xy, -HEAD);
        float a = length(q.xz - float2(0, 41)) ;
        add(r, extrude(a - 11.5f, q.y, -16, 8, 1.6), WEIGHT);
        // Tapered plate.
        float half_ = mix(13.0f, 23.0f, smoothstep(4.0f, 36.0f, q.y));
        float2 pl = float2(abs(q.x) - half_, abs(q.y - 54) - 50);
        float plate = length(max(pl + 5, 0.0f)) + min(max(pl.x + 5, pl.y + 5), 0.0f) - 5;
        // Slots for the cartridge screws.
        float slot = min(sdBox2(q.xy - float2(-10.5, 60), float2(2.6, 13), 2.6), sdBox2(q.xy - float2(10.5, 60), float2(2.6, 13), 2.6));
        float holes = 1e5;
        for (int i = 0; i < 3; i++) holes = min(holes, length(q.xy - float2(0, 26 + i * 12)) - 3.0f);
        plate = max(plate, -min(slot, holes));
        add(r, extrude(plate, q.z, 40, 46, 1.4) * 0.9f, SHELL);
        add(r, extrude(sdBox2(q.xy - float2(0, 76), float2(18.5, 34), 3.5), q.z, 17, 38, 2), CART);
        for (int s = -1; s <= 1; s += 2) {
            float3 k = q - float3(s * 10.5, 60, 0);
            float head = extrude(length(k.xy) - 4.6f, k.z, 44, 49, 1);
            float groove = sdBox2(rot(k.xy, 0.5f + s), float2(6, 0.8), 0.1);
            add(r, max(head, -max(groove, 47.4f - k.z)), SCREW);
        }
        float l = min(capsule(q, float3(20, 62, 43), float3(37, 68, 44), 2.3), capsule(q, float3(37, 68, 44), float3(43, 88, 48), 2.3));
        add(r, l, LIFT);
    }
    return r;
}

static float2 map(float3 p, UA) {
    float2 r = float2(1e5, 0);
    bool plane = u.mode == 4;
    if (!plane) {
        // Deck with the platter's well cut out of it.
        float2 c = p.xy - float2(500, 375);
        float body = sdBox2(c, float2(500, 375), 54);
        float deck = extrudeChamfer(body, p.z, -92, 0, 3.2);
        float rs = length(p.xy - SP);
        float well = extrude(rs - (PLATTER + 10), p.z, -22, 30, 0.5);
        // Its edge is bevelled.
        float cone = max((rs - (PLATTER + 10) - (p.z + 3)) * 0.70710678f, -(p.z + 4));
        float d = max(max(deck, -well), -cone);
        int id = DECK;
        if (p.z < -5) id = FRONT;
        if (p.z < -0.15f && p.z > -5 && body > -4.5f) id = CHAMFER;
        if (rs < PLATTER + 13.2f && p.z < -0.15f) id = p.z > -3.05f ? CHAMFER : WELL;
        add(r, d, id);

        // Platter with a bevelled rim, and its rubber mat.
        if (rs < PLATTER + 40) {
            float pl = extrude(rs - PLATTER, p.z, -16, 8, 2.8);
            add(r, pl, RIM);
            float m = extrude(rs - 331, p.z, 4, 11, 1.2);
            m += 0.35f * smoothstep(0.75f, 1.0f, cos(rs * 0.698f));
            add(r, m * 0.9f, MAT);
            if (u.mode >= 2) {
                float v = extrude(rs - RECORD, p.z, 11, 14.2, 1.5);
                // Raised rim and label.
                v = min(v, extrude(abs(rs - (RECORD - 3.2f)) - 2.6f, p.z, 12, 15, 1.2));
                v = min(v, extrude(rs - (LABEL + 4), p.z, 12, 15, 0.9));
                add(r, v, rs < LABEL + 0.5f ? PAPER : VINYL);
            }
        }

        // Arm base (fixed): plate, polished ring, pillar.
        {
            float2 b = p.xy - PV; float br = length(b);
            if (br < 130) {
                add(r, extrudeChamfer(br - 80, p.z, -2, 9, 2.6), br > 77 ? RING : BASE);
                float dial = extrude(br - 62, p.z, 8, 20, 2.2);
                float kn = atan2(b.y, b.x);
                if (br > 58) dial += 0.5f * smoothstep(-0.2f, 0.6f, cos(kn * 72));
                add(r, dial * 0.8f, DIAL);
                add(r, extrude(br - 50, p.z, 18, 24, 1.5), BASE);
                add(r, extrude(br - 24, p.z, 18, 40, 2), PILLAR);
            } else add(r, br - 90, BASE);
        }
        // Arm rest: a post with a clip.
        {
            float3 q = p; q.xy = rot(p.xy - PV, -REST) - float2(19.8, 262);
            float bd = length(q.xy);
            if (bd < 60) {
                add(r, extrude(bd - 17, q.z, -2, 5, 1.6), RING);
                add(r, extrude(bd - 9.5f, q.z, 0, 36, 1.5), REST_ID);
                float clip = extrude(sdBox2(q.xy, float2(17, 8), 4), q.z, 30, 52, 2);
                float gap = min(length(q.xz - float2(0, 50)) - 8.4f, sdBox2(q.xz - float2(0, 60), float2(7.6, 10), 1));
                add(r, max(clip, -gap), REST_ID);
            } else add(r, bd - 30, REST_ID);
        }
        // The name: raised steel letters with bevelled edges.
        {
            float2 l = p.xy - LOGO_AREA.xy;
            if (all(l > 0.0f) && all(l < LOGO_AREA.zw) && p.z < 6) {
                constexpr sampler sm(filter::linear, address::clamp_to_edge);
                float e = tx.sample(sm, l / LOGO_AREA.zw, level(0)).r;
                add(r, extrudeChamfer(e, p.z, -2, 1.5, 0.3) * 0.85f, LOGO);
            }
        }
        // Lens surround of the power light.
        {
            float b = length(p.xy - float2(944, 700));
            add(r, extrude(abs(b - 9.5f) - 1.7f, p.z, -2, 1.3, 0.8), LEDRING);
        }
    }
    if (u.mode >= 3 && u.noArm == 0) {
        float3 q = p; q.xy = rot(p.xy - PV, -u.armAngle);
        float2 a = mapArm(q);
        if (a.x < r.x) r = a;
    }
    return r;
}

static float3 normalAt(float3 p, UA) {
    const float e = 0.06; float3 n = 0;
    for (int i = 0; i < 4; i++) {
        float3 k = 0.5773f * (2.0f * float3(((i + 3) >> 1) & 1, (i >> 1) & 1, i & 1) - 1.0f);
        n += k * map(p + k * e, UU).x;
    }
    return normalize(n);
}

// Softboxes: centre, half-axes, radiance.
struct Light { float3 c, a, b; float3 e; };
static float3 sky(float3 o, float3 d) {
    Light L[4] = {
        { float3(-420, -620, 820), float3(520, -260, 60), float3(150, 330, 330), float3(1.0, 0.985, 0.96) * 12.5 },
        { float3(1420, 1240, 760), float3(-420, 330, 40), float3(60, 120, 260), float3(0.93, 0.97, 1.0) * 9.5 },
        { float3(420, -160, 1250), float3(620, 0, 0), float3(0, 210, 0), float3(1, 1, 1) * 0.9 },
        { float3(380, 1250, 520), float3(640, 0, 0), float3(0, 30, 120), float3(1, 0.98, 0.95) * 1.3 },
    };
    float best = 1e9; float3 res = mix(float3(0.016), float3(0.06), saturate(d.z * 0.5f + 0.5f));
    // A bright wall low down behind the light, for the polished edges.
    float2 hz = d.xy / max(length(d.xy), 1e-4f);
    res += float3(1.0, 0.99, 0.97) * 2.1f * pow(saturate(dot(hz, normalize(float2(-0.5, -0.86))) * 0.5f + 0.5f), 3.0f) * smoothstep(0.75f, 0.0f, abs(d.z - 0.05f));
    // And a dimmer one opposite, which gives the record its second glare.
    res += float3(0.95, 0.98, 1.0) * 0.8f * pow(saturate(dot(hz, normalize(float2(0.6, 0.8)))), 4.0f) * smoothstep(0.9f, 0.1f, abs(d.z - 0.3f));
    for (int i = 0; i < 4; i++) {
        float3 n = cross(L[i].a, L[i].b);
        float t = dot(L[i].c - o, n) / dot(d, n);
        if (t < 1 || t > best) continue;
        float3 h = o + d * t - L[i].c;
        float s = dot(h, L[i].a) / dot(L[i].a, L[i].a), v = dot(h, L[i].b) / dot(L[i].b, L[i].b);
        if (abs(s) > 1 || abs(v) > 1) continue;
        best = t;
        // Brighter in the middle, like a real diffuser.
        float f = smoothstep(1.0f, 0.45f, abs(s)) * smoothstep(1.0f, 0.5f, abs(v)) * (0.72f + 0.28f * (1 - s * s) * (1 - v * v));
        res = mix(res, L[i].e, f);
    }
    return res;
}

struct Mat { float3 f0, diff; float ax, ay; float3 t; float bump; };

static Mat material(int id, thread float3 &p, thread float3 &n) {
    Mat m; m.f0 = 0.04; m.diff = 0.02; m.ax = m.ay = 0.3; m.t = float3(1, 0, 0); m.bump = 0;
    float2 rv = p.xy - SP; float rs = length(rv); float3 radial = float3(rv / max(rs, 1e-3f), 0);
    switch (id) {
    case DECK: m.f0 = float3(0.078, 0.078, 0.083); m.diff = 0.012; m.ax = m.ay = 0.40; m.bump = 0.028; break;
    case FRONT: m.f0 = float3(0.078, 0.078, 0.083); m.diff = 0.012; m.ax = m.ay = 0.36; break;
    case CHAMFER: m.f0 = float3(0.58, 0.58, 0.60); m.diff = 0; m.ax = m.ay = 0.20; break;
    case WELL: m.f0 = 0.03; m.diff = 0.006; m.ax = m.ay = 0.4; break;
    case RIM: m.f0 = float3(0.60, 0.605, 0.62); m.diff = 0; m.ax = 0.30; m.ay = 0.11; m.t = radial; break;
    case MAT: m.f0 = 0.035; m.diff = 0.014; m.ax = m.ay = 0.55; break;
    case VINYL: {
        m.diff = 0.0022; m.t = radial;
        // Grooves: wide sideways scatter, almost a mirror along the groove.
        // Each ring differs a little, and louder passages differ in bands.
        float ring = hash(float2(floor(rs * 1.15f), 3.0));
        float band = 0.5f + 0.5f * sin(rs * 0.21f + 2.2f * sin(rs * 0.043f));
        m.f0 = 0.04f + 0.062f * ring * ring + 0.026f * band;
        m.ax = 0.36f + 0.16f * ring + 0.08f * band; m.ay = 0.085f + 0.045f * ring;
        float gap = 1e5; float g[4] = { 192, 231, 262, 289 };
        for (int i = 0; i < 4; i++) gap = min(gap, abs(rs - g[i]) - 1.5f);
        bool smooth_ = gap < 0 || rs < LEADOUT - 1 || rs > RECORD - 9;
        if (smooth_) { m.ax = m.ay = 0.075; m.f0 = 0.048; }
        else if (n.z > 0.9f) n = normalize(n + radial * (hash(float2(floor(rs * 1.7f), 9.0)) - 0.5f) * 0.14f);
        break; }
    case PAPER: m.f0 = 0.02; m.diff = 0.03; m.ax = m.ay = 0.6; break;
    case BASE: m.f0 = float3(0.09, 0.09, 0.095); m.diff = 0.01; m.ax = m.ay = 0.36; m.bump = 0.03; break;
    case RING: m.f0 = float3(0.62, 0.62, 0.64); m.diff = 0; m.ax = m.ay = 0.12; break;
    case PIVOT: m.f0 = float3(0.28, 0.28, 0.29); m.diff = 0.004; m.ax = m.ay = 0.22; break;
    case REST_ID: m.f0 = float3(0.34, 0.34, 0.35); m.diff = 0.004; m.ax = m.ay = 0.24; break;
    case LOGO: {
        // Brushed along the letters' reading direction: long fine scratches.
        float row = hash(float2(floor(p.y * 2.6f), floor((p.x + 40 * hash(float2(floor(p.y * 2.6f), 5))) / 26)));
        float fine = hash(float2(floor(p.y * 1.3f), 17.0));
        m.f0 = float3(0.80, 0.795, 0.785) * (0.62f + 0.5f * row); m.diff = 0.0; m.t = float3(1, 0, 0);
        m.ax = 0.10; m.ay = 0.34f + 0.12f * fine;
        if (n.z > 0.95f) n = normalize(n + float3(0, (row - 0.5f) * 0.22f, 0));
        else { m.ax = m.ay = 0.14; m.f0 = 0.85; }
        break; }
    case DIAL: m.f0 = float3(0.46, 0.46, 0.475); m.diff = 0; m.ax = m.ay = 0.2; break;
    case PILLAR: m.f0 = float3(0.2, 0.2, 0.21); m.diff = 0; m.ax = m.ay = 0.25; break;
    case TUBE: m.f0 = float3(0.84, 0.85, 0.87); m.diff = 0; m.ax = m.ay = 0.085; break;
    case WEIGHT: m.f0 = float3(0.30, 0.30, 0.315); m.diff = 0.003; m.ax = m.ay = 0.17; break;
    case YOKE: m.f0 = float3(0.72, 0.725, 0.74); m.diff = 0; m.ax = m.ay = 0.15; break;
    case SCREW: m.f0 = float3(0.78, 0.78, 0.79); m.diff = 0; m.ax = m.ay = 0.12; break;
    case SHELL: m.f0 = float3(0.17, 0.17, 0.178); m.diff = 0.006; m.ax = m.ay = 0.27; m.bump = 0.02; break;
    case CART: m.f0 = 0.045; m.diff = float3(0.55, 0.012, 0.035); m.ax = m.ay = 0.16; break;
    case LIFT: m.f0 = float3(0.82, 0.82, 0.84); m.diff = 0; m.ax = m.ay = 0.10; break;
    case LEDRING: m.f0 = float3(0.4); m.diff = 0; m.ax = m.ay = 0.15; break;
    }
    return m;
}

static bool march(float3 o, float3 d, float tmax, UA, thread float &t, thread int &id) {
    t = 0;
    for (int i = 0; i < 160; i++) {
        float3 p = o + d * t;
        if (p.z > 90 && d.z > 0) return false;
        if (p.z < -120 || t > tmax) return false;
        float2 h = map(p, UU);
        if (h.x < 0.012f) { id = int(h.y); return true; }
        t += h.x * 0.92f;
    }
    id = 0;
    return false;
}

static float3 sampleVNDF(float3 v, float ax, float ay, float2 x) {
    float3 vh = normalize(float3(ax * v.x, ay * v.y, v.z));
    float l = vh.x * vh.x + vh.y * vh.y;
    float3 t1 = l > 0 ? float3(-vh.y, vh.x, 0) / sqrt(l) : float3(1, 0, 0);
    float3 t2 = cross(vh, t1);
    float r = sqrt(x.x), phi = 2 * M_PI_F * x.y, a = r * cos(phi), b = r * sin(phi), s = 0.5f * (1 + vh.z);
    b = (1 - s) * sqrt(max(0.0f, 1 - a * a)) + s * b;
    float3 nh = a * t1 + b * t2 + sqrt(max(0.0f, 1 - a * a - b * b)) * vh;
    return normalize(float3(ax * nh.x, ay * nh.y, max(0.0f, nh.z)));
}
static float G1(float3 w, float ax, float ay) {
    float t = (ax * ax * w.x * w.x + ay * ay * w.y * w.y) / max(w.z * w.z, 1e-6f);
    return 2 / (1 + sqrt(1 + t));
}

static float3 trace(float3 o, float3 d, float3 view, int bounces, UA, thread uint &s, thread int &first, bool primary) {
    float3 thr = 1, res = 0;
    for (int b = 0; b < bounces; b++) {
        float t; int id;
        if (!march(o, d, 2600, UU, t, id)) { if (primary && b == 0) { first = 0; return 0; } return res + thr * min(sky(o, d), 12.0f); }
        float3 p = o + d * t;
        if (b == 0) first = id;
        float3 n = normalAt(p, UU);
        if (id == LOGO && n.z < 0.9f) res += thr * float3(0.04f + 0.6f * pow(saturate(dot(n, normalize(float3(-0.5, -0.8, 0.5)))), 2.0f));
        if (id == LOGO && n.z > 0.9f) {
            // The letters get their own reflector card, as in product
            // photography: flat steel here would only mirror the dark studio.
            float row = hash(float2(floor(p.y * 2.6f), floor((p.x + 40 * hash(float2(floor(p.y * 2.6f), 5))) / 26)));
            float broad = hash(float2(floor(p.y * 0.9f), 23.0));
            float x = p.x + 0.55f * (p.y - 694);
            float card = 0.15f + 0.36f * exp(-pow((x - 82) / 30, 2.0f)) + 0.20f * exp(-pow((x - 160) / 22, 2.0f));
            card *= 1.0f - 0.016f * (p.y - 694);
            res += thr * float3(0.985, 0.99, 1.0) * card * (0.40f + 0.50f * row + 0.26f * broad);
        }
        Mat m = material(id, p, n);
        if (m.bump > 0) {
            float2 k = floor(p.xy * 1.3f);
            n = normalize(n + float3(hash(k) - 0.5f, hash(k + 71.3f) - 0.5f, 0) * m.bump * 2);
        }
        // The projection is parallel, but light reflects towards a camera at a
        // finite distance; otherwise flat surfaces would be one flat colour.
        float3 v = (b == 0 && primary) ? normalize(view - p) : -d;
        float3 T = normalize(m.t - n * dot(m.t, n)); float3 B = cross(n, T);
        float3 lv = float3(dot(v, T), dot(v, B), dot(v, n));
        if (lv.z < 0.02f) lv = normalize(float3(lv.xy, 0.02));
        float3 fr = m.f0 + (1 - m.f0) * pow(1 - lv.z, 5.0f);
        float ps = clamp(max(fr.x, max(fr.y, fr.z)) / (max(fr.x, max(fr.y, fr.z)) + max(m.diff.x, max(m.diff.y, m.diff.z)) + 1e-5f), 0.15f, 0.97f);
        if (max(m.diff.x, max(m.diff.y, m.diff.z)) <= 0) ps = 1;
        float3 ld;
        if (rnd(s) < ps) {
            float3 h = sampleVNDF(lv, m.ax, m.ay, float2(rnd(s), rnd(s)));
            ld = reflect(-lv, h);
            if (ld.z <= 0) return res;
            float3 F = m.f0 + (1 - m.f0) * pow(1 - saturate(dot(lv, h)), 5.0f);
            thr *= F * G1(ld, m.ax, m.ay) / ps;
        } else {
            float r = sqrt(rnd(s)), phi = 2 * M_PI_F * rnd(s);
            ld = float3(r * cos(phi), r * sin(phi), sqrt(max(0.0f, 1 - r * r)));
            thr *= m.diff * (1 - fr) / (1 - ps);
        }
        d = normalize(T * ld.x + B * ld.y + n * ld.z);
        o = p + n * 0.06f;
        if (b > 1) { float q = max(thr.x, max(thr.y, thr.z)); if (rnd(s) > q) return res; thr /= min(q, 1.0f); }
    }
    return res;
}

static bool belongs(int id, uint mode) {
    switch (mode) {
    case 0: return id != 0;
    case 1: return id == RIM || id == MAT;
    case 2: return id == VINYL || id == PAPER;
    case 3: return id >= TUBE && id <= LIFT || id == PIVOT || id == SCREW || id == WEIGHT || id == YOKE;
    }
    return false;
}

kernel void render(texture2d<float, access::read_write> acc [[texture(0)]], texture2d<float> tx [[texture(1)]], constant U &u [[buffer(0)]], uint2 g [[thread_position_in_grid]]) {
    uint s = (g.x * 1973u + g.y * 9277u + u.frame * 26699u) | 1u; pcg(s); pcg(s);
    float4 c = u.frame == 0 ? float4(0) : acc.read(g);
    for (int k = 0; k < 4; k++) {
        float2 px = u.origin + (float2(g) + float2(rnd(s), rnd(s))) / u.scale;
        float3 view = float3(500, 470, 2300);
        if (u.mode == 4) {
            // Light reaching a matt surface at the record's height.
            float3 o = float3(rot(px, u.armAngle) + PV, 12);
            float r = sqrt(rnd(s)), phi = 2 * M_PI_F * rnd(s);
            float3 d = float3(r * cos(phi), r * sin(phi), sqrt(max(0.0f, 1 - r * r)));
            float t; int id;
            float v = march(o, d, 900, UU, t, id) ? 0.0f : sky(o, d).g;
            c += float4(v, v, v, 1);
        } else if (u.mode == 3) {
            float3 o = float3(rot(px, u.armAngle) + PV, 85);
            int id; float3 l = trace(o, float3(0, 0, -1), view, 5, UU, s, id, true);
            if (belongs(id, 3) && !(id == PIVOT && length(px) > 60) && !(id == WEIGHT && false)) c += float4(l, 1);
        } else {
            // Slightly oblique for the deck, so its front edge shows; circles stay circles.
            float3 d = normalize(float3(0, -u.shear, -1));
            float3 o = float3(px, 0) - d / -d.z * 85;
            int id; float3 l = trace(o, d, view, 5, UU, s, id, true);
            if (belongs(id, u.mode)) c += float4(l, 1);
        }
    }
    acc.write(c, g);
}
"""#

struct U {
    var w: UInt32, h: UInt32, mode: UInt32, frame: UInt32
    var origin: SIMD2<Float>
    var scale: Float, armAngle: Float, shear: Float
    var noArm: UInt32
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Turntable")
let samples = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1200
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let pipeline = try device.makeComputePipelineState(function: device.makeLibrary(source: shader, options: nil).makeFunction(name: "render")!)

/// The name as a signed distance field, in scene units, over LOGO_AREA.
let logo: MTLTexture = {
    let k = 8, w = 220 * k, h = 60 * k
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.scaleBy(x: CGFloat(k), y: CGFloat(k))
    let font = NSFont.systemFont(ofSize: 27, weight: .medium, width: .expanded)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "LeoTube", attributes: [.font: font, .kern: 1.1, .foregroundColor: NSColor.white]))
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.textPosition = CGPoint(x: 14, y: 14)
    CTLineDraw(line, ctx)
    print("logo width", CTLineGetTypographicBounds(line, nil, nil, nil))
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self), stride = ctx.bytesPerRow
    // Exact distance transform (Felzenszwalb), inside and outside.
    func edt(_ inside: Bool) -> [Float] {
        var f = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { f[y * w + x] = ((px[y * stride + x] > 127) == inside) ? 0 : 1e10 } }
        func pass(_ n: Int, _ get: (Int) -> Float, _ put: (Int, Float) -> Void) {
            var v = [Int](repeating: 0, count: n), z = [Float](repeating: 0, count: n + 1), k = 0
            let g = (0..<n).map(get)
            z[0] = -.infinity; z[1] = .infinity
            for q in 1..<n {
                var s = ((g[q] + Float(q * q)) - (g[v[k]] + Float(v[k] * v[k]))) / Float(2 * q - 2 * v[k])
                while s <= z[k] { k -= 1; s = ((g[q] + Float(q * q)) - (g[v[k]] + Float(v[k] * v[k]))) / Float(2 * q - 2 * v[k]) }
                k += 1; v[k] = q; z[k] = s; z[k + 1] = .infinity
            }
            k = 0
            for q in 0..<n { while z[k + 1] < Float(q) { k += 1 }; put(q, Float((q - v[k]) * (q - v[k])) + g[v[k]]) }
        }
        for x in 0..<w { pass(h, { f[$0 * w + x] }, { f[$0 * w + x] = $1 }) }
        for y in 0..<h { pass(w, { f[y * w + $0] }, { f[y * w + $0] = $1 }) }
        return f
    }
    let toInk = edt(true), toPaper = edt(false)
    var sdf = [Float](repeating: 0, count: w * h)
    for i in 0..<(w * h) { sdf[i] = (toInk[i].squareRoot() - toPaper[i].squareRoot()) / Float(k) }
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
    d.usage = .shaderRead; d.storageMode = .shared
    let t = device.makeTexture(descriptor: d)!
    t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: sdf, bytesPerRow: w * 4)
    return t
}()

/// Accumulated linear colour and sample count per pixel.
func render(mode: UInt32, origin: CGPoint, size: CGSize, scale: Double, armAngle: Double = 0, shear: Double = 0, noArm: Bool = false) -> (px: [SIMD4<Float>], w: Int, h: Int) {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]; desc.storageMode = .shared
    let tex = device.makeTexture(descriptor: desc)!
    for frame in 0..<max(1, samples / 4) {
        var u = U(w: UInt32(w), h: UInt32(h), mode: mode, frame: UInt32(frame), origin: SIMD2(Float(origin.x), Float(origin.y)),
                  scale: Float(scale), armAngle: Float(armAngle), shear: Float(shear), noArm: noArm ? 1 : 0)
        let cb = queue.makeCommandBuffer()!, enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(pipeline); enc.setTexture(tex, index: 0); enc.setTexture(logo, index: 1); enc.setBytes(&u, length: MemoryLayout<U>.stride, index: 0)
        enc.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        if let e = cb.error { fatalError("\(e)") }
    }
    var px = [SIMD4<Float>](repeating: .zero, count: w * h)
    tex.getBytes(&px, bytesPerRow: w * 16, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    return (px, w, h)
}

/// Filmic curve (Hable-like shoulder through ACES fit), sRGB, dithered.
func encode(_ x: Float, _ noise: Float) -> UInt8 {
    let v = max(0, x * 0.92)
    let m = min(1, (v * (2.51 * v + 0.03)) / (v * (2.43 * v + 0.59) + 0.14))
    let g = m <= 0.0031308 ? m * 12.92 : 1.055 * pow(m, 1 / 2.4) - 0.055
    return UInt8(max(0, min(255, g * 255 + noise)))
}

func image(_ r: (px: [SIMD4<Float>], w: Int, h: Int), total: Float) -> CGImage {
    var out = [UInt8](repeating: 0, count: r.w * r.h * 4)
    var rng = SystemRandomNumberGenerator()
    for i in 0..<(r.w * r.h) {
        let p = r.px[i]
        guard p.w > 0 else { continue }
        let a = min(1, p.w / total), n = Float.random(in: 0..<1, using: &rng)
        let c = SIMD3(Float(encode(p.x / p.w, n)), Float(encode(p.y / p.w, n)), Float(encode(p.z / p.w, n)))
        for k in 0..<3 { out[i * 4 + k] = UInt8(min(255, c[k] * a)) }
        out[i * 4 + 3] = UInt8(a * 255)
    }
    return CGImage(width: r.w, height: r.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: r.w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: CGDataProvider(data: Data(out) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func save(_ img: CGImage, _ name: String) {
    let url = outDir.appendingPathComponent("\(name).heic")
    let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
    guard CGImageDestinationFinalize(dst) else { fatalError("couldn't write \(name)") }
    print(name, img.width, img.height, (try! Data(contentsOf: url)).count / 1024, "KB")
}

if CommandLine.arguments.count > 3 {
    // Preview: the corner with the name, enlarged.
    save(image(render(mode: 0, origin: CGPoint(x: -20, y: 600), size: CGSize(width: 300, height: 170), scale: 4, shear: 0.11), total: Float(max(1, samples / 4) * 4)), "preview-logo")
    exit(0)
}

let total = Float(max(1, samples / 4) * 4)
let t0 = Date()
let scale = 1.7

// Sizes here match TurntableArt.
let margin = 90.0
save(image(render(mode: 0, origin: CGPoint(x: -margin, y: -margin), size: CGSize(width: 1000 + 2 * margin, height: 760 + 2 * margin), scale: scale, shear: 0.11), total: total), "deck")
save(image(render(mode: 1, origin: CGPoint(x: 390 - 356, y: 380 - 356), size: CGSize(width: 712, height: 712), scale: scale), total: total), "platter")
save(image(render(mode: 2, origin: CGPoint(x: 390 - 332, y: 380 - 332), size: CGSize(width: 664, height: 664), scale: scale), total: total), "record")
let armAngle = 32.0 * .pi / 180
save(image(render(mode: 3, origin: CGPoint(x: -90, y: -185), size: CGSize(width: 180, height: 760), scale: 2, armAngle: armAngle), total: total), "arm")

// The arm's shadow: how much light it takes away.
let lit = render(mode: 4, origin: CGPoint(x: -300, y: -400), size: CGSize(width: 600, height: 1160), scale: 0.6, armAngle: armAngle)
let open = render(mode: 4, origin: CGPoint(x: -300, y: -400), size: CGSize(width: 600, height: 1160), scale: 0.6, armAngle: armAngle, noArm: true)
var sh = [UInt8](repeating: 0, count: lit.w * lit.h * 4)
for i in 0..<(lit.w * lit.h) { // Fade out the faint, wide part so the bitmap has no visible border.
    let x = Float(i % lit.w) / Float(lit.w), y = Float(i / lit.w) / Float(lit.h)
    let edge = min(1, min(min(x, 1 - x), min(y, 1 - y)) / 0.18)
    let dark = max(0, 1 - lit.px[i].x / max(open.px[i].x, 1e-4) - 0.02) * edge * edge * (3 - 2 * edge)
    sh[i * 4 + 3] = UInt8(max(0, min(255, dark * 255))) }
save(CGImage(width: lit.w, height: lit.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: lit.w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: CGDataProvider(data: Data(sh) as CFData)!,
             decode: nil, shouldInterpolate: true, intent: .defaultIntent)!, "arm-shadow")
print("done in", Int(Date().timeIntervalSince(t0)), "s")
