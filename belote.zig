const std = @import("std");

const stdout = std.io.getStdOut().writer();
const allocator = std.heap.page_allocator;
const rndGen = std.rand.DefaultPrng;
var rnd = rndGen.init(0);

const NB_COLORS: usize = 4;
const NB_CARDS: usize = 8;
const ALL_CARDS: usize = NB_CARDS * NB_COLORS;
const NB_PLAYERS = 4;

const Color = u4;
const Height = u4;
const Card = packed struct { h: Height, c: Color };
const Deck = struct { nb: u8, t: [ALL_CARDS]Card };
const Hand = struct { nb: [NB_COLORS]u8, t: [NB_CARDS][NB_COLORS]Height };
const Game = [NB_PLAYERS]Hand;

const ZDECK = Deck{ .nb = 0, .t = [_]Card{Card{ .h = 0, .c = 0 }} ** ALL_CARDS };
const ZHAND = Hand{ .nb = [_]u8{0} ** NB_COLORS, .t = [_][NB_COLORS]Height{[_]Height{0} ** NB_COLORS} ** NB_CARDS };
const FDECK = blk: {
    var d: Deck = undefined;
    for (&d.t, 0..) |*v, i| {
        v.*.c = @as(Color, @intCast(i % 4));
        v.*.h = @as(Height, @intCast(i / 4));
    }
    d.nb = NB_COLORS * NB_CARDS;
    break :blk d;
};
const CVALLS = [NB_CARDS][NB_COLORS]i32{ [_]i32{ 20, 14, 11, 10, 4, 3, 0, 0 }, [_]i32{ 11, 10, 4, 3, 2, 0, 0, 0 }, [_]i32{ 11, 10, 4, 3, 2, 0, 0, 0 }, [_]i32{ 11, 10, 4, 3, 2, 0, 0, 0 } };

pub fn draw_deck(d: *Deck) void {
    var ds: Deck = FDECK;
    for (&d.t, 0..) |*v, i| {
        var nb: usize = NB_COLORS * NB_CARDS - i;
        var j: usize = rnd.random().int(usize) % nb;
        v.* = ds.t[j];
        ds.t[j] = ds.t[nb - 1];
    }
    d.nb = ALL_CARDS;
}

pub fn draw_cards(d: *Deck, ha: *Hand, nb: u32) void {
    for (0..nb) |_| {
        var j: usize = rnd.random().int(usize) % d.nb;
        var c: Color = d.t[j].c;
        var h: Height = d.t[j].h;
        d.t[j] = d.t[d.nb - 1];
        d.nb -= 1;
        ha.t[c][ha.nb[c]] = h;
        ha.nb[c] += 1;
    }
}

pub fn print_deck(d: Deck) !void {
    try stdout.print("nb={d}\n", .{d.nb});
    for (0..d.nb) |i| {
        try stdout.print("{d} {d}\n", .{ d.t[i].c, d.t[i].h });
    }
}

pub fn print_hand(ha: Hand) !void {
    for (ha.nb, 0..) |v, i| {
        try stdout.print("nb={d}\n", .{v});
        for (0..v) |j| {
            try stdout.print("{d}\n", .{ha.t[i][j]});
        }
    }
}

const Vals = i16;
const VALS_MIN: Vals = std.math.minInt(i16);
const VALS_MAX: Vals = std.math.maxInt(i16);
const Depth = u8;
var gd: Game = undefined;
var ply: [NB_PLAYERS]Card = undefined;
var nbp: usize = undefined;
var nump: usize = undefined;
var score: Vals = undefined;

fn ab(alpha: Vals, beta: Vals, color: Color, depth: Depth) Vals {
    var a = alpha;
    var b = beta;
    var g: Vals = if (color % 2 == 0) VALS_MIN else VALS_MAX;

    while (a < b) {
        const v = ab(a, b, (color + 1) % NB_COLORS, depth + 1);
        if (color % 2 == 0) {
            g = @max(v, g);
            a = @max(a, g);
        } else {
            g = @min(v, g);
            b = @min(b, g);
        }
    }
    return g;
}

pub fn main() !void {
    var d: Deck = ZDECK;
    var z: Hand = ZHAND;
    draw_deck(&d);
    try print_deck(d);
    draw_cards(&d, &z, 10);
    try print_hand(z);
    try print_deck(d);
}
