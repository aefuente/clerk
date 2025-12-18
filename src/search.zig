const std = @import("std");
const issue = @import("issue.zig");
const Allocator = std.mem.Allocator;
const context = struct {};

pub fn filterAndSort(allocator: Allocator, query: []const u8, candidates: []issue.Issue, threshold: usize) ![]issue.Issue {
    var tmp = try std.ArrayList(FuzzyMatch).initCapacity(allocator, 10);
    defer tmp.deinit(allocator);
    const norm_query = try normalize(allocator, query);
    defer allocator.free(norm_query);
    for (candidates, 0..)  |c, idx| {
        const norm_title = try normalize(allocator, c.title);
        defer allocator.free(norm_title);
        const s =try scoreTitle(allocator, norm_query, norm_title);
        if (s > threshold) {
            try tmp.append(allocator, FuzzyMatch{.issue = try issue.Issue.deepCopy(allocator, candidates[idx]), .score = s});
        }
    }

    std.sort.heap(FuzzyMatch, tmp.items, context{}, cmp);
    var result = try allocator.alloc(issue.Issue, tmp.items.len);
    for (tmp.items, 0..) |c, idx| {
        result[idx] = c.issue;
    }
    return result;
}

fn normalize(allocator: Allocator, text: []const u8) ![]u8{ 
    var title = try allocator.alloc(u8, text.len);
    var i: usize = 0;

    for (text) |c| {
        if (std.ascii.isAlphanumeric(c) or c == ' ') {
            title[i] = std.ascii.toLower(c);
            i += 1;
        }
    }
    return title;
}

fn scoreTitle(
    allocator: std.mem.Allocator,
    norm_query: []const u8,
    norm_title: []const u8,
) !usize {
    var score: usize = 0;
    var query_it = std.mem.splitAny(u8, norm_query, " ");
    var title_it = std.mem.splitAny(u8, norm_title, " ");

    if (title_it.next()) |t_token| {
        if (std.mem.indexOf(u8, t_token, norm_query) != null) {
            score += 60;
        }
    }

    while (query_it.next()) |q_token | {
        if (std.mem.indexOf(u8, norm_title, q_token) != null) {
                score += 10;
        }
    }

    if (std.mem.indexOf(u8, norm_title, norm_query) != null) {
        score += 25;
    }

    if (score < 20) {
        const fuzzy = try fuzzyScore(
            allocator,
            norm_query,
            norm_title,
        );

        if (fuzzy > 60) {
            score += fuzzy;
        }
    }

    return score;
}

fn max(a: usize, b: usize) usize {
    if (a > b) {return a;}
    return b;
}

fn fuzzyScore(
    allocator: std.mem.Allocator,
    query: []const u8,
    title: []const u8,
) !usize {
    const dist = try LevenshteinDistance(allocator, query, title);
    const max_len = max(query.len, title.len);
    if (max_len == 0) return 0;
    return @divFloor((100 * (max_len - dist)), max_len);
}

pub fn LevenshteinDistance(allocator: Allocator, a: []const u8, b: []const u8) !usize {

    const m = a.len;
    const n = b.len;
    var prev_row = try allocator.alloc(usize, n+1);
    defer allocator.free(prev_row);

    for (0..n+1) | i | {
        prev_row[i] = i;
    }

    var cur_row = try allocator.alloc(usize, n+1);
    defer allocator.free(cur_row);

    for (1..m+1) | i | {
        cur_row[0] = i;
        for (1..n+1) | j | {
            if (std.ascii.toLower(a[i-1]) == std.ascii.toLower(b[j-1])) {
                cur_row[j] = prev_row[j-1];
            }else {
                var min = cur_row[j-1];
                if (min > prev_row[j]) {
                    min = prev_row[j];
                }
                if (min > prev_row[j-1]){
                    min = prev_row[j-1];
                }
                cur_row[j] = 1 + min;
            }
        }
        std.mem.swap([]usize, &prev_row, &cur_row);
    }
    return cur_row[n];
}

const FuzzyMatch = struct {
    issue: issue.Issue,
    score: usize,
};


fn cmp(ctx: context, lhs: FuzzyMatch, rhs: FuzzyMatch) bool {
    _ = ctx;
    if (lhs.score >= rhs.score) {
        return true;
    }
    return false;
}
