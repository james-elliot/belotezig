const std = @import("std");

const STDOUT = std.io.getStdOut().writer();
const ALLOCATOR = std.heap.page_allocator;
const RNDGEN = std.rand.DefaultPrng;
var rnd = RNDGEN.init(0);

const NB_COLORS: usize = 4;
const NB_CARDS: usize = 8;
const ALL_CARDS: usize = NB_CARDS * NB_COLORS;
const NB_PLAYERS = 4;

const Color = u8;
const Height = u8;
const Card = packed struct { h: Height, c: Color };
const Deck = struct { nb: u8, t: [ALL_CARDS]Card };
const Hand = struct { nb: [NB_COLORS]u8, t: [NB_CARDS][NB_COLORS]Height };
const Game = [NB_PLAYERS]Hand;

const INVALID_COLOR: Color = std.math.maxInt(Color);
const TRUMP: Color = 0;
const INVALID_HEIGHT: Height = std.math.maxInt(Height);
const ZDECK = Deck{ .nb = 0, .t = [_]Card{Card{ .h = 0, .c = 0 }} ** ALL_CARDS };
const ZHAND = Hand{ .nb = [_]u8{0} ** NB_COLORS, .t = [_][NB_COLORS]Height{[_]Height{0} ** NB_COLORS} ** NB_CARDS };
const FDECK = blk: {
    var d: Deck = undefined;
    for (&d.t, 0..) |*v, i| {
        v.*.c = @as(Color, @intCast(i % 4));
        v.*.h = @as(Height, @intCast(i / 4));
    }
    d.nb = ALL_CARDS;
    break :blk d;
};
const CVALS = [NB_COLORS][NB_CARDS]Vals{
    [_]Vals{ 0, 0, 3, 4, 10, 11, 14, 20 },
    [_]Vals{ 0, 0, 0, 2, 3, 4, 10, 11 },
    [_]Vals{ 0, 0, 0, 2, 3, 4, 10, 11 },
    [_]Vals{ 0, 0, 0, 2, 3, 4, 10, 11 },
};

pub fn draw_deck(d: *Deck) void {
    var ds: Deck = FDECK;
    for (&d.t, 0..) |*v, i| {
        var nb: usize = ALL_CARDS - i;
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
    try STDOUT.print("nb={d}\n", .{d.nb});
    for (0..d.nb) |i| {
        try STDOUT.print("({d},{d}) ", .{ d.t[i].c, d.t[i].h });
    }
    try STDOUT.print("\n", .{});
}

pub fn print_hand(ha: Hand) !void {
    for (ha.nb, 0..) |v, i| {
        try STDOUT.print("{d}: ", .{i});
        for (0..v) |j| {
            try STDOUT.print("{d} ", .{ha.t[i][j]});
        }
        try STDOUT.print("\n", .{});
    }
}

pub fn print_game(g: Game) !void {
    var names = [_][]const u8{ "N", "E", "S", "O" };
    for (g, 0..) |v, i| {
        try STDOUT.print("{s}\n", .{names[i]});
        try print_hand(v);
    }
}

const Vals = i16;
const VALS_MIN: Vals = std.math.minInt(i16);
const VALS_MAX: Vals = std.math.maxInt(i16);
const Depth = u8;
const Nump = u8;
const Toplay = struct { nb: usize, t: [NB_CARDS]struct { c: u8, i: usize } };
var gd: Game = undefined;
var exact: bool = true;

fn ab(alpha: Vals, beta: Vals, col: Color, hcard: Height, hplay: Nump, c_val: Vals, cut: bool, nump: Nump, nbp: Nump, score1: Vals, score2: Vals, depth: Depth) Vals {
    var a = alpha;
    var b = beta;
    var ha: *Hand = &gd[nump];
    var vl: Toplay = undefined;
    vl.nb = 0;

    if (nbp == 0) { //First card of the ply, everything is valid
        for (ha.nb, 0..) |n, c| {
            for (0..n) |i| {
                vl.t[vl.nb].c = @as(Color, @intCast(c));
                vl.t[vl.nb].i = i;
                vl.nb += 1;
            }
        }
    } else { // Not the first card
        if (ha.nb[col] != 0) { // I have the required color
            if (col != TRUMP) { // If it is not TRUMP, every card of the color is valid
                for (0..ha.nb[col]) |i| {
                    vl.t[vl.nb].c = col;
                    vl.t[vl.nb].i = i;
                    vl.nb += 1;
                }
            } else { // If it is TRUMP, then only higher cards than the current better is valid, except if I don't have any better
                var higher: Height = std.math.minInt(Height);
                for (0..ha.nb[TRUMP]) |i| {
                    higher = @max(higher, ha.t[TRUMP][i]);
                }
                if (higher < hcard) higher = std.math.minInt(Height);
                for (0..ha.nb[TRUMP]) |i| {
                    if (ha.t[TRUMP][i] >= higher) {
                        vl.t[vl.nb].c = TRUMP;
                        vl.t[vl.nb].i = i;
                        vl.nb += 1;
                    }
                }
            }
        } else { // I don't have the required color
            if ((ha.nb[TRUMP] == 0) or // If i don't have any TRUMP or...
                ((!cut) and (nump % 2 == hplay % 2))) // if nobody has cut yet and my partner has the best card...
            { // then all cards are valids
                for (ha.nb, 0..) |n, c| {
                    for (0..n) |i| {
                        vl.t[vl.nb].c = @as(Color, @intCast(c));
                        vl.t[vl.nb].i = i;
                        vl.nb += 1;
                    }
                }
            } else { // I have to under or over cut
                var higher: Height = std.math.minInt(Height);
                if (cut) {
                    for (0..ha.nb[TRUMP]) |i| {
                        higher = @max(higher, ha.t[TRUMP][i]);
                    }
                    if (higher < hcard) higher = std.math.minInt(Height);
                }
                for (0..ha.nb[TRUMP]) |i| {
                    if (ha.t[TRUMP][i] >= higher) {
                        vl.t[vl.nb].c = TRUMP;
                        vl.t[vl.nb].i = i;
                        vl.nb += 1;
                    }
                }
            }
        }
    }

    var g: Vals = if (nump % 2 == 0) VALS_MIN else VALS_MAX;
    var i: usize = 0;
    while ((a < b) and (i < vl.nb)) {
        var c = vl.t[i].c;
        var h = ha.t[c][vl.t[i].i];
        ha.t[c][vl.t[i].i] = ha.t[c][ha.nb[c] - 1];
        ha.nb[c] -= 1;
        var nc_val = c_val + CVALS[c][h];
        var nhcard = hcard;
        var nhplay = hplay;
        var ncol = col;
        var v: Vals = undefined;
        if (nbp == 0) {
            nhcard = h;
            nhplay = nump;
            ncol = c;
        } else {
            if ((col == TRUMP) or (cut)) {
                if ((c == TRUMP) and (h > hcard)) {
                    nhcard = h;
                    nhplay = nump;
                }
            } else {
                if ((c == col) and (h > hcard)) {
                    nhcard = h;
                    nhplay = nump;
                }
            }
        }
        var ncut: bool = cut;
        if ((c == TRUMP) and (col != TRUMP)) {
            ncut = true;
        }
        if (nbp != NB_PLAYERS - 1) {
            v = ab(a, b, ncol, nhcard, nhplay, nc_val, ncut, (nump + 1) % NB_PLAYERS, nbp + 1, score1, score2, depth - 1);
        } else {
            var nscore1: Vals = score1;
            var nscore2: Vals = score2;
            if (hplay % 2 == 0) {
                nscore1 += c_val;
                if (depth == 1) {
                    nscore1 += 10;
                }
            } else {
                nscore2 += c_val;
                if (depth == 1) {
                    nscore2 += 10;
                }
            }
            if (((!exact) and ((nscore1 > 81) or (nscore2 > 81))) or (depth == 1)) {
                ha.nb[c] += 1;
                ha.t[c][vl.t[i].i] = h;
                return nscore1 - nscore2;
            }
            v = ab(a, b, 0, 0, 0, 0, false, nump, 0, nscore1, nscore2, depth - 1);
        }
        ha.nb[c] += 1;
        ha.t[c][vl.t[i].i] = h;

        if (nump % 2 == 0) {
            g = @max(v, g);
            a = @max(a, g);
        } else {
            g = @min(v, g);
            b = @min(b, g);
        }
        i += 1;
    }
    return g;
}

pub fn main() !void {
    var d: Deck = ZDECK;
    draw_deck(&d);
    try print_deck(d);
    for (&gd) |*h| {
        draw_cards(&d, h, NB_CARDS);
    }
    try print_hand(gd[0]);
    try print_deck(d);
    try print_game(gd);
    var res = ab(-1, 1, 0, 0, 0, 0, false, 0, 0, 0, 0, 32);
    try STDOUT.print("res={d}\n", .{res});
}
