package boltspark.ui.shaders;

/**
 * Analytic, texture-free coverage for BoltUI's small editor icons.
 *
 * Every icon is evaluated as a signed-distance shape in the fragment shader.
 * Screen-space derivatives keep the edge transition one physical pixel wide,
 * including on diagonal strokes and when an icon lands between pixel centers.
 */
class UiIconShader extends hxsl.Shader {
    static var SRC = {
        @input var input:{
            var uv:Vec2;
        };

        var pixelColor:Vec4;

        @param var iconKind:Int;
        @param var stroke:Float;

        function segment(p:Vec2, a:Vec2, b:Vec2):Float {
            var pa = p - a;
            var ba = b - a;
            var h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            return length(pa - ba * h) - stroke * 0.5;
        }

        function cross2(a:Vec2, b:Vec2):Float {
            return a.x * b.y - a.y * b.x;
        }

        function triangle(p:Vec2, a:Vec2, b:Vec2, c:Vec2):Float {
            var orientation = cross2(b - a, c - a) >= 0.0 ? 1.0 : -1.0;
            var sideA = cross2(b - a, p - a) * orientation;
            var sideB = cross2(c - b, p - b) * orientation;
            var sideC = cross2(a - c, p - c) * orientation;
            var edgeDistance = min(
                segment(p, a, b),
                min(segment(p, b, c), segment(p, c, a))
            ) + stroke * 0.5;
            return min(sideA, min(sideB, sideC)) >= 0.0
                ? -edgeDistance
                : edgeDistance;
        }

        function circle(p:Vec2, center:Vec2, radius:Float):Float {
            return length(p - center) - radius;
        }

        function circleStroke(p:Vec2, center:Vec2, radius:Float):Float {
            return abs(circle(p, center, radius)) - stroke * 0.5;
        }

        function box(p:Vec2, center:Vec2, halfSize:Vec2):Float {
            var q = abs(p - center) - halfSize;
            return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
        }

        function roundedBox(p:Vec2, center:Vec2, halfSize:Vec2, radius:Float):Float {
            var q = abs(p - center) - halfSize + vec2(radius);
            return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
        }

        function boxStroke(p:Vec2, center:Vec2, halfSize:Vec2, radius:Float):Float {
            return abs(roundedBox(p, center, halfSize, radius)) - stroke * 0.5;
        }

        function playTriangle(p:Vec2):Float {
            var slope = 0.6956522;
            var normalizer = 0.8209052;
            var left = 0.32 - p.x;
            var upper = (0.18 + slope * (p.x - 0.32) - p.y) * normalizer;
            var lower = (p.y - (0.82 - slope * (p.x - 0.32))) * normalizer;
            return max(left, max(upper, lower));
        }

        function fragment() {
            var p = input.uv;
            var d = 1.0;

            // Add
            if (iconKind == 1) {
                d = min(
                    segment(p, vec2(0.50, 0.20), vec2(0.50, 0.80)),
                    segment(p, vec2(0.20, 0.50), vec2(0.80, 0.50))
                );
            }
            // Trash
            else if (iconKind == 2) {
                d = segment(p, vec2(0.30, 0.30), vec2(0.35, 0.84));
                d = min(d, segment(p, vec2(0.35, 0.84), vec2(0.65, 0.84)));
                d = min(d, segment(p, vec2(0.65, 0.84), vec2(0.70, 0.30)));
                d = min(d, segment(p, vec2(0.22, 0.28), vec2(0.78, 0.28)));
                d = min(d, segment(p, vec2(0.40, 0.18), vec2(0.60, 0.18)));
            }
            // Cube
            else if (iconKind == 3) {
                d = segment(p, vec2(0.50, 0.12), vec2(0.84, 0.32));
                d = min(d, segment(p, vec2(0.84, 0.32), vec2(0.50, 0.52)));
                d = min(d, segment(p, vec2(0.50, 0.52), vec2(0.16, 0.32)));
                d = min(d, segment(p, vec2(0.16, 0.32), vec2(0.50, 0.12)));
                d = min(d, segment(p, vec2(0.16, 0.32), vec2(0.16, 0.70)));
                d = min(d, segment(p, vec2(0.16, 0.70), vec2(0.50, 0.90)));
                d = min(d, segment(p, vec2(0.50, 0.90), vec2(0.84, 0.70)));
                d = min(d, segment(p, vec2(0.84, 0.70), vec2(0.84, 0.32)));
                d = min(d, segment(p, vec2(0.50, 0.52), vec2(0.50, 0.90)));
            }
            // Search
            else if (iconKind == 4) {
                d = circleStroke(p, vec2(0.43, 0.42), 0.24);
                d = min(d, segment(p, vec2(0.60, 0.59), vec2(0.84, 0.83)));
            }
            // Play
            else if (iconKind == 5) {
                d = playTriangle(p);
            }
            // Pause
            else if (iconKind == 6) {
                d = roundedBox(p, vec2(0.35, 0.50), vec2(0.08, 0.30), 0.035);
                d = min(d, roundedBox(p, vec2(0.65, 0.50), vec2(0.08, 0.30), 0.035));
            }
            // Stop
            else if (iconKind == 7) {
                d = roundedBox(p, vec2(0.50, 0.50), vec2(0.25, 0.25), 0.055);
            }
            // Move
            else if (iconKind == 8) {
                d = segment(p, vec2(0.50, 0.19), vec2(0.50, 0.81));
                d = min(d, segment(p, vec2(0.19, 0.50), vec2(0.81, 0.50)));
                d = min(d, triangle(p, vec2(0.50, 0.08), vec2(0.38, 0.24), vec2(0.62, 0.24)));
                d = min(d, triangle(p, vec2(0.50, 0.92), vec2(0.62, 0.76), vec2(0.38, 0.76)));
                d = min(d, triangle(p, vec2(0.08, 0.50), vec2(0.24, 0.62), vec2(0.24, 0.38)));
                d = min(d, triangle(p, vec2(0.92, 0.50), vec2(0.76, 0.38), vec2(0.76, 0.62)));
            }
            // Rotate
            else if (iconKind == 9) {
                var ring = circleStroke(p, vec2(0.50, 0.52), 0.31);
                var gap = box(p, vec2(0.76, 0.24), vec2(0.18, 0.17));
                d = max(ring, -gap);
                d = min(d, segment(p, vec2(0.70, 0.18), vec2(0.83, 0.34)));
                d = min(d, segment(p, vec2(0.83, 0.34), vec2(0.64, 0.37)));
            }
            // Scale
            else if (iconKind == 10) {
                d = boxStroke(p, vec2(0.37, 0.63), vec2(0.15, 0.15), 0.0);
                d = min(d, segment(p, vec2(0.48, 0.52), vec2(0.82, 0.18)));
                d = min(d, segment(p, vec2(0.59, 0.18), vec2(0.82, 0.18)));
                d = min(d, segment(p, vec2(0.82, 0.18), vec2(0.82, 0.41)));
            }
            // Chevron down
            else if (iconKind == 11) {
                d = segment(p, vec2(0.24, 0.38), vec2(0.50, 0.64));
                d = min(d, segment(p, vec2(0.50, 0.64), vec2(0.76, 0.38)));
            }
            // Chevron right
            else if (iconKind == 12) {
                d = segment(p, vec2(0.38, 0.24), vec2(0.64, 0.50));
                d = min(d, segment(p, vec2(0.64, 0.50), vec2(0.38, 0.76)));
            }
            // Console
            else if (iconKind == 13) {
                d = boxStroke(p, vec2(0.50, 0.50), vec2(0.38, 0.33), 0.07);
                d = min(d, segment(p, vec2(0.27, 0.38), vec2(0.39, 0.50)));
                d = min(d, segment(p, vec2(0.39, 0.50), vec2(0.27, 0.62)));
                d = min(d, segment(p, vec2(0.50, 0.64), vec2(0.70, 0.64)));
            }
            // Sliders
            else if (iconKind == 14) {
                d = segment(p, vec2(0.16, 0.28), vec2(0.84, 0.28));
                d = min(d, segment(p, vec2(0.16, 0.50), vec2(0.84, 0.50)));
                d = min(d, segment(p, vec2(0.16, 0.72), vec2(0.84, 0.72)));
                d = min(d, circle(p, vec2(0.36, 0.28), 0.09));
                d = min(d, circle(p, vec2(0.66, 0.50), 0.09));
                d = min(d, circle(p, vec2(0.45, 0.72), 0.09));
            }
            // Hierarchy
            else if (iconKind == 15) {
                d = segment(p, vec2(0.30, 0.22), vec2(0.30, 0.78));
                d = min(d, segment(p, vec2(0.30, 0.36), vec2(0.63, 0.36)));
                d = min(d, segment(p, vec2(0.30, 0.68), vec2(0.63, 0.68)));
                d = min(d, circle(p, vec2(0.70, 0.36), 0.085));
                d = min(d, circle(p, vec2(0.70, 0.68), 0.085));
            }
            // Close
            else if (iconKind == 16) {
                d = segment(p, vec2(0.25, 0.25), vec2(0.75, 0.75));
                d = min(d, segment(p, vec2(0.75, 0.25), vec2(0.25, 0.75)));
            }
            // Grid
            else if (iconKind == 17) {
                d = segment(p, vec2(0.25, 0.12), vec2(0.25, 0.88));
                d = min(d, segment(p, vec2(0.50, 0.12), vec2(0.50, 0.88)));
                d = min(d, segment(p, vec2(0.75, 0.12), vec2(0.75, 0.88)));
                d = min(d, segment(p, vec2(0.12, 0.25), vec2(0.88, 0.25)));
                d = min(d, segment(p, vec2(0.12, 0.50), vec2(0.88, 0.50)));
                d = min(d, segment(p, vec2(0.12, 0.75), vec2(0.88, 0.75)));
            }
            // More
            else if (iconKind == 18) {
                d = circle(p, vec2(0.25, 0.50), 0.07);
                d = min(d, circle(p, vec2(0.50, 0.50), 0.07));
                d = min(d, circle(p, vec2(0.75, 0.50), 0.07));
            }
            // Chevron up
            else if (iconKind == 19) {
                d = segment(p, vec2(0.24, 0.62), vec2(0.50, 0.36));
                d = min(d, segment(p, vec2(0.50, 0.36), vec2(0.76, 0.62)));
            }
            // Chamfered Boltspark brand tile.
            else if (iconKind == 20) {
                var centered = abs(p - vec2(0.50));
                d = max(
                    max(centered.x - 0.50, centered.y - 0.50),
                    (centered.x + centered.y - 0.81) * 0.7071068
                );
            }
            // Lightning cutout used over the brand tile.
            else if (iconKind == 21) {
                var p0 = vec2(0.524, 0.095);
                var p1 = vec2(0.238, 0.524);
                var p2 = vec2(0.476, 0.524);
                var p3 = vec2(0.381, 0.905);
                var p4 = vec2(0.762, 0.381);
                var p5 = vec2(0.524, 0.381);
                d = triangle(p, p5, p0, p1);
                d = min(d, triangle(p, p5, p1, p2));
                d = min(d, triangle(p, p2, p3, p4));
                d = min(d, triangle(p, p2, p4, p5));
            }
            // Status indicator.
            else if (iconKind == 22) {
                d = circle(p, vec2(0.50), 0.42);
            }
            // Linked scale proportions.
            else if (iconKind == 23) {
                d = circleStroke(p, vec2(0.35, 0.35), 0.19);
                d = min(d, circleStroke(p, vec2(0.65, 0.65), 0.19));
                d = min(d, segment(p, vec2(0.41, 0.41), vec2(0.59, 0.59)));
            }
            // Unlinked scale proportions: the same chain with a clear slash.
            else if (iconKind == 24) {
                d = circleStroke(p, vec2(0.34, 0.34), 0.17);
                d = min(d, circleStroke(p, vec2(0.66, 0.66), 0.17));
                d = min(d, segment(p, vec2(0.18, 0.82), vec2(0.82, 0.18)));
            }
            // Reset to the row's canonical transform value.
            else if (iconKind == 25) {
                var resetRing = circleStroke(p, vec2(0.50, 0.52), 0.29);
                var resetGap = box(p, vec2(0.25, 0.25), vec2(0.18, 0.16));
                d = max(resetRing, -resetGap);
                d = min(d, segment(p, vec2(0.19, 0.35), vec2(0.19, 0.16)));
                d = min(d, segment(p, vec2(0.19, 0.16), vec2(0.38, 0.16)));
            }

            var antialias = max(fwidth(d) * 0.5, 0.0001);
            var coverage = 1.0 - smoothstep(-antialias, antialias, d);
            pixelColor.a *= coverage;
        }
    };
}
