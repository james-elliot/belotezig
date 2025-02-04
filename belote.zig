const std = @import("std");

const DEBUG = false;

const STDOUT = std.io.getStdOut().writer();
const ALLOCATOR = std.heap.page_allocator;
const RNDGEN = std.Random.DefaultPrng;
var rnd: std.Random.Xoshiro256 = undefined;

const NB_COLORS: usize = 4;
const NB_CARDS: usize = 8;
const ALL_CARDS: usize = NB_CARDS * NB_COLORS;
const NB_PLAYERS = 4;

const Color = u8;
const Height = u8;
const Card = packed struct { h: Height, c: Color };
const Deck = struct { nb: u8, t: [ALL_CARDS]Card };
const Hand = struct { nb: [NB_COLORS]u8, t: [NB_COLORS][NB_CARDS]Height };
const Game = [NB_PLAYERS]Hand;

const INVALID_COLOR: Color = std.math.maxInt(Color);
const TRUMP: Color = 0;
const INVALID_HEIGHT: Height = std.math.maxInt(Height);
const ZDECK = Deck{ .nb = 0, .t = [_]Card{Card{ .h = 0, .c = 0 }} ** ALL_CARDS };
const ZHAND = Hand{ .nb = [_]u8{0} ** NB_COLORS, .t = [_][NB_CARDS]Height{[_]Height{0} ** NB_CARDS} ** NB_COLORS };
const ZGAME: Game = [_]Hand{ZHAND} ** NB_PLAYERS;
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

const CCARDS = [NB_COLORS][NB_CARDS]*const [2:0]u8{
    [NB_CARDS]*const [2:0]u8{ "7 ", "8 ", "D ", "R ", "10", "A ", "14", "20" },
    [NB_CARDS]*const [2:0]u8{ "7 ", "8 ", "9 ", "V ", "D ", "R ", "10", "A " },
    [NB_CARDS]*const [2:0]u8{ "7 ", "8 ", "9 ", "V ", "D ", "R ", "10", "A " },
    [NB_CARDS]*const [2:0]u8{ "7 ", "8 ", "9 ", "V ", "D ", "R ", "10", "A " },
};

pub fn draw_deck(d: *Deck) void {
    var ds: Deck = FDECK;
    for (&d.t, 0..) |*v, i| {
        const nb: usize = ALL_CARDS - i;
        const j: usize = rnd.random().int(usize) % nb;
        v.* = ds.t[j];
        ds.t[j] = ds.t[nb - 1];
    }
    d.nb = ALL_CARDS;
}

pub fn draw_cards(d: *Deck, ha: *Hand, nb: u32) void {
    for (0..nb) |_| {
        const j: usize = rnd.random().int(usize) % d.nb;
        const c: Color = d.t[j].c;
        const h: Height = d.t[j].h;
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
            try STDOUT.print("{s} ", .{CCARDS[i][ha.t[i][j]]});
        }
        for (v..NB_CARDS) |_| {
            try STDOUT.print("   ", .{});
        }
    }
    try STDOUT.print("\n", .{});
}

pub fn print_game(g: Game) !void {
    const names = [_][]const u8{ "N", "E", "S", "O" };
    for (g, 0..) |v, i| {
        try STDOUT.print("{s}\n", .{names[i]});
        try print_hand(v);
    }
}

pub fn rotate_game(g: *Game) void {
    const ha: Hand = g[0];
    for (0..NB_COLORS - 1) |i| {
        g[i] = g[i + 1];
    }
    g[NB_COLORS - 1] = ha;
}

pub fn rotate_hand(h: *Hand) void {
    //const Hand = struct { nb: [NB_COLORS]u8, t: [NB_COLORS][NB_CARDS]Height };
    const n: u8 = h.nb[0];
    const t: [NB_CARDS]Height = h.t[0];
    for (0..NB_COLORS - 1) |i| {
        h.nb[i] = h.nb[i + 1];
        h.t[i] = h.t[i + 1];
    }
    h.nb[NB_COLORS - 1] = n;
    h.t[NB_COLORS - 1] = t;
}

const Vals = i16;
const VALS_MIN: Vals = std.math.minInt(i16);
const VALS_MAX: Vals = std.math.maxInt(i16);
const Depth = u8;
const Nump = u8;
const Toplay = struct { nb: usize, t: [NB_CARDS]struct { c: Color, i: usize } };
//var gd: Game = undefined;

fn ab(alpha: Vals, beta: Vals, col: Color, hcard: Height, hplay: Nump, c_val: Vals, cut: bool, nump: Nump, nbp: Nump, score1: Vals, score2: Vals, depth: Depth, exact: bool, gd: *Game) Vals {
    if (DEBUG) {
        STDOUT.print("alpha={d} beta={d} col={d} hcard={d} hplay={d} c_val={d} cur={any} nump={d} nbp={d} score1={d} score2={d} depth={d}\n", .{ alpha, beta, col, hcard, hplay, c_val, cut, nump, nbp, score1, score2, depth }) catch std.os.exit(255);
        print_game(gd) catch std.os.exit(255);
    }

    var a = alpha;
    var b = beta;
    var ha: *Hand = &gd[nump];
    var vl: Toplay = undefined;
    vl.nb = 0;

    if (nbp == 0) { //First card of the ply, everything is valid
        var low: [NB_COLORS]usize = [NB_COLORS]usize{ 0, 0, 0, 0 };
        for (0..NB_COLORS) |c| {
            var hp: usize = undefined;
            var hv: Height = std.math.minInt(Height);
            if (ha.nb[c] > 0) {
                for (gd, 0..) |lha, i| {
                    if ((lha.nb[c] > 0) and (lha.t[c][0] > hv)) {
                        hv = lha.t[c][0];
                        hp = i;
                    }
                }
                if (((hp + nump) % 2 == 0) and (hv != std.math.minInt(Height))) {
                    vl.t[vl.nb].c = @as(Color, @intCast(c));
                    vl.t[vl.nb].i = 0;
                    vl.nb += 1;
                    low[c] = 1;
                }
            }
        }
        for (ha.nb, 0..) |n, c| {
            if (low[c] < n) {
                for (low[c]..n) |i| {
                    vl.t[vl.nb].c = @as(Color, @intCast(c));
                    //                    vl.t[vl.nb].i = n - 1 - i;
                    vl.t[vl.nb].i = i;
                    vl.nb += 1;
                }
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

    if (DEBUG) {
        STDOUT.print("vl.nb={d}\n", .{vl.nb}) catch std.os.exit(255);
        for (0..vl.nb) |i| {
            STDOUT.print("({d},{d}) ", .{ vl.t[i].c, ha.t[vl.t[i].c][vl.t[i].i] }) catch std.os.exit(255);
        }
        STDOUT.print("\n", .{}) catch std.os.exit(255);
    }

    var g: Vals = if (nump % 2 == 0) VALS_MIN else VALS_MAX;
    var i: usize = 0;
    while ((a < b) and (i < vl.nb)) {
        const c = vl.t[i].c;
        const h = ha.t[c][vl.t[i].i];
        ha.t[c][vl.t[i].i] = ha.t[c][ha.nb[c] - 1];
        ha.nb[c] -= 1;
        const nc_val = c_val + CVALS[c][h];
        var nhcard = hcard;
        var nhplay = hplay;
        var ncol = col;
        var ncut: bool = cut;
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
                if (((c == col) and (h > hcard)) or (c == TRUMP)) {
                    nhcard = h;
                    nhplay = nump;
                }
                if ((c == TRUMP) and (col != TRUMP)) {
                    ncut = true;
                }
            }
        }
        if (nbp != NB_PLAYERS - 1) {
            v = ab(a, b, ncol, nhcard, nhplay, nc_val, ncut, (nump + 1) % NB_PLAYERS, nbp + 1, score1, score2, depth - 1, exact, gd);
        } else {
            var nscore1: Vals = score1;
            var nscore2: Vals = score2;
            if (nhplay % 2 == 0) {
                nscore1 += nc_val;
                if (depth == 1) {
                    nscore1 += 10;
                }
            } else {
                nscore2 += nc_val;
                if (depth == 1) {
                    nscore2 += 10;
                }
            }
            if (DEBUG) {
                STDOUT.print("nscore1={d} nscore2={d}\n", .{ nscore1, nscore2 }) catch std.os.exit(255);
            }
            if (((!exact) and ((nscore1 > 81) or (nscore2 > 81))) or (depth == 1)) {
                v = nscore1 - nscore2;
            } else {
                v = ab(a, b, 0, 0, 0, 0, false, nhplay, 0, nscore1, nscore2, depth - 1, exact, gd);
            }
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
        if (DEBUG) {
            STDOUT.print("vl.nb={d},g={d},a={d} b={d} c={d} h={d} ncol={d} nhcard={d} nhplay={d} nc_val={d} cur={any} nump={d} nbp={d} score1={d} score2={d} depth={d}\n", .{ vl.nb, g, a, b, c, h, ncol, nhcard, nhplay, nc_val, cut, nump, nbp, score1, score2, depth }) catch std.os.exit(255);
        }
        i += 1;
    }
    return g;
}

fn cmpByValue(context: void, a: Height, b: Height) bool {
    return std.sort.asc(Height)(context, b, a);
}

fn test1() !void {
    var d: Deck = ZDECK;
    var gd: Game = ZGAME;
    const nb = NB_CARDS;
    draw_deck(&d);
    try print_deck(d);
    for (&gd) |*h| {
        draw_cards(&d, h, nb);
        for (0..NB_COLORS) |i| {
            std.sort.insertion(Height, h.t[i][0..h.nb[i]], {}, cmpByValue);
        }
    }
    try print_game(gd);
    const res = ab(-1, 1, 0, 0, 0, 0, false, 0, 0, 0, 0, nb * NB_PLAYERS, false, &gd);
    try STDOUT.print("res={d}\n", .{res});
}

pub fn main() !void {
    var seed: u64 = 0;
    var args = std.process.args();
    if (args.skip()) {
        if (args.next()) |w| {
            seed = std.fmt.parseInt(u64, w, 10) catch 0;
        }
    }
    try STDOUT.print("seed={d}\n", .{seed});
    rnd = RNDGEN.init(seed);

    var d: Deck = ZDECK;
    var gd: Game = ZGAME;
    draw_deck(&d);
    draw_cards(&d, &gd[0], 6);
    for (0..NB_COLORS) |_| {
        const nb = 10;
        var succ: u32 = 0;
        try print_game(gd);
        for (0..nb) |_| {
            var d2 = d;
            var gd2 = gd;
            draw_cards(&d2, &gd2[0], 2);
            for (1..NB_COLORS) |i| {
                draw_cards(&d2, &gd2[i], 8);
            }
            for (&gd2) |*h| {
                for (0..NB_COLORS) |i| {
                    std.sort.insertion(Height, h.t[i][0..h.nb[i]], {}, cmpByValue);
                }
            }
            //        try print_game(gd2);
            const res = ab(-1, 1, 0, 0, 0, 0, false, 0, 0, 0, 0, 32, false, &gd2);
            if (res > 0) succ += 1;
            //        try STDOUT.print("res={d}\n", .{res});
        }
        try STDOUT.print("succ={d}\n", .{succ});
        rotate_hand(&gd[0]);
    }
    try test1();
}
