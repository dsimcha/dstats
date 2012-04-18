/**Basic information theory.  Joint entropy, mutual information, conditional
 * mutual information.  This module uses the base 2 definition of these
 * quantities, i.e, entropy, mutual info, etc. are output in bits.
 *
 * Author:  David Simcha*/
 /*
 * License:
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

module dstats.infotheory;

import std.traits, std.math, std.typetuple, std.functional, std.range,
       std.array, std.typecons, std.algorithm;

import dstats.base, dstats.alloc;
import dstats.summary : sum;
import dstats.distrib : chiSquareCDFR;

import dstats.tests : toContingencyScore, gTestContingency;

version(unittest) {
    import std.stdio, std.bigint, dstats.tests : gTestObs;

    void main() {}
}

/**This function calculates the Shannon entropy of a forward range that is
 * treated as frequency counts of a set of discrete observations.
 *
 * Examples:
 * ---
 * double uniform3 = entropyCounts([4, 4, 4]);
 * assert(approxEqual(uniform3, log2(3)));
 * double uniform4 = entropyCounts([5, 5, 5, 5]);
 * assert(approxEqual(uniform4, 2));
 * ---
 */
double entropyCounts(T)(T data)
if(isForwardRange!(T) && doubleInput!(T)) {
    auto save = data.save();
    return entropyCounts(save, sum!(T, double)(data));
}

double entropyCounts(T)(T data, double n)
if(isIterable!(T)) {
    immutable double nNeg1 = 1.0 / n;
    double entropy = 0;
    foreach(value; data) {
        if(value == 0)
            continue;
        double pxi = cast(double) value * nNeg1;
        entropy -= pxi * log2(pxi);
    }
    return entropy;
}

unittest {
    double uniform3 = entropyCounts([4, 4, 4].dup);
    assert(approxEqual(uniform3, log2(3)));
    double uniform4 = entropyCounts([5, 5, 5, 5].dup);
    assert(approxEqual(uniform4, 2));
    assert(entropyCounts([2,2].dup)==1);
    assert(entropyCounts([5.1,5.1,5.1,5.1].dup)==2);
    assert(approxEqual(entropyCounts([1,2,3,4,5].dup), 2.1492553971685));
}

template FlattenType(T...) {
    alias FlattenTypeImpl!(T).ret FlattenType;
}

template FlattenTypeImpl(T...) {
    static if(T.length == 0) {
        alias TypeTuple!() ret;
    } else {
        T[0] j;
        static if(is(typeof(j._jointRanges))) {
            alias TypeTuple!(typeof(j._jointRanges), FlattenType!(T[1..$])) ret;
        } else {
            alias TypeTuple!(T[0], FlattenType!(T[1..$])) ret;
        }
    }
}

private Joint!(FlattenType!(T, U)) flattenImpl(T, U...)(T start, U rest) {
    static if(rest.length == 0) {
        return start;
    } else static if(is(typeof(rest[0]._jointRanges))) {
        return flattenImpl(jointImpl(start.tupleof, rest[0]._jointRanges), rest[1..$]);
    } else {
        return flattenImpl(jointImpl(start.tupleof, rest[0]), rest[1..$]);
    }
}

Joint!(FlattenType!(T)) flatten(T...)(T args) {
    static assert(args.length > 0);
    static if(is(typeof(args[0]._jointRanges))) {
        auto myTuple = args[0];
    } else {
        auto myTuple = jointImpl(args[0]);
    }
    static if(args.length == 1) {
        return myTuple;
    } else {
        return flattenImpl(myTuple, args[1..$]);
    }
}

/**Bind a set of ranges together to represent a joint probability distribution.
 *
 * Examples:
 * ---
 * auto foo = [1,2,3,1,1];
 * auto bar = [2,4,6,2,2];
 * auto e = entropy(joint(foo, bar));  // Calculate joint entropy of foo, bar.
 * ---
 */
Joint!(FlattenType!(T)) joint(T...)(T args) {
    return jointImpl(flatten(args).tupleof);
}

Joint!(T) jointImpl(T...)(T args) {
    return Joint!(T)(args);
}

/**Iterate over a set of ranges by value in lockstep and return an ObsEnt,
 * which is used internally by entropy functions on each iteration.*/
struct Joint(T...) {
    T _jointRanges;

    @property ObsEnt!(ElementsTuple!(T)) front() {
        alias ElementsTuple!(T) E;
        alias ObsEnt!(E) rt;
        rt ret;
        foreach(ti, elem; _jointRanges) {
            ret.tupleof[ti] = elem.front;
        }
        return ret;
    }

    void popFront() {
        foreach(ti, elem; _jointRanges) {
            _jointRanges[ti].popFront;
        }
    }

    @property bool empty() {
        foreach(elem; _jointRanges) {
            if(elem.empty) {
                return true;
            }
        }
        return false;
    }

    static if(T.length > 0 && allSatisfy!(hasLength, T)) {
        @property size_t length() {
            size_t ret = size_t.max;
            foreach(range; _jointRanges) {
                auto len = range.length;
                if(len < ret) {
                    ret = len;
                }
            }
            return ret;
        }
    }
}

template ElementsTuple(T...) {
    static if(T.length == 1) {
        alias TypeTuple!(Unqual!(ElementType!(T[0]))) ElementsTuple;
    } else {
        alias TypeTuple!(Unqual!(ElementType!(T[0])), ElementsTuple!(T[1..$]))
            ElementsTuple;
    }
}

private template Comparable(T) {
    enum bool Comparable = is(typeof({
        T a;
        T b;
        return a < b; }));
}

static assert(Comparable!ubyte);
static assert(Comparable!ubyte);

struct ObsEnt(T...) {
    T compRep;
    alias compRep this;

    static if(anySatisfy!(hasIndirections, T)) {

        // Then there's indirection involved.  We can't just do all our
        // comparison and hashing operations bitwise.
        hash_t toHash() {
            hash_t sum = 0;
            foreach(i, elem; this.tupleof) {
                sum *= 11;
                static if(is(elem : long) && elem.sizeof <= hash_t.sizeof) {
                    sum += elem;
                } else static if(__traits(compiles, elem.toHash)) {
                    sum += elem.toHash;
                } else {
                    auto ti = typeid(typeof(elem));
                    sum += ti.getHash(&elem);
                }
            }
            return sum;
        }

        bool opEquals(const ref typeof(this) rhs) const {
            foreach(ti, elem; this.tupleof) {
                if(elem != rhs.tupleof[ti])
                    return false;
            }
            return true;
        }
    }
    // Else just use the default runtime functions for hash and equality.


    static if(allSatisfy!(Comparable, T)) {
        int opCmp(const ref typeof(this) rhs) const {
            foreach(ti, elem; this.tupleof) {
                if(rhs.tupleof[ti] < elem) {
                    return -1;
                } else if(rhs.tupleof[ti] > elem) {
                    return 1;
                }
            }
            return 0;
        }
    }
}

// Whether we can use StackTreeAA, or whether we have to use a regular AA for
// entropy.
private template NeedsHeap(T) {
    static if(!hasIndirections!(ForeachType!(T))) {
        enum bool NeedsHeap = false;
    } else static if(isArray!(T)) {
        enum bool NeedsHeap = false;
    } else static if(is(Joint!(typeof(T.init.tupleof)))
           && is(T == Joint!(typeof(T.init.tupleof)))
           && allSatisfy!(isArray, typeof(T.init.tupleof))) {
        enum bool NeedsHeap = false;
    } else {
        enum bool NeedsHeap = true;
    }
}

unittest {
    auto foo = filter!"a"(cast(uint[][]) [[1]]);
    auto bar = filter!("a")([1,2,3][]);
    static assert(NeedsHeap!(typeof(foo)));
    static assert(!NeedsHeap!(typeof(bar)));
    static assert(NeedsHeap!(Joint!(uint[], typeof(foo))));
    static assert(!NeedsHeap!(Joint!(uint[], typeof(bar))));
    static assert(!NeedsHeap!(Joint!(uint[], uint[])));
}

/**Calculates the joint entropy of a set of observations.  Each input range
 * represents a vector of observations. If only one range is given, this reduces
 * to the plain old entropy.  Input range must have a length.
 *
 * Note:  This function specializes if ElementType!(T) is a byte, ubyte, or
 * char, resulting in a much faster entropy calculation.  When possible, try
 * to provide data in the form of a byte, ubyte, or char.
 *
 * Examples:
 * ---
 * int[] foo = [1, 1, 1, 2, 2, 2, 3, 3, 3];
 * double entropyFoo = entropy(foo);  // Plain old entropy of foo.
 * assert(approxEqual(entropyFoo, log2(3)));
 * int[] bar = [1, 2, 3, 1, 2, 3, 1, 2, 3];
 * double HFooBar = entropy(joint(foo, bar));  // Joint entropy of foo and bar.
 * assert(approxEqual(HFooBar, log2(9)));
 * ---
 */
double entropy(T)(T data)
if(isIterable!(T)) {
    static if(!hasLength!(T)) {
        return entropyImpl!(uint, T)(data);
    } else {
        if(data.length <= ubyte.max) {
            return entropyImpl!(ubyte, T)(data);
        } else if(data.length <= ushort.max) {
            return entropyImpl!(ushort, T)(data);
        } else {
            return entropyImpl!(uint, T)(data);
        }
    }
}

private double entropyImpl(U, T)(T data)
if((ForeachType!(T).sizeof > 1 || is(ForeachType!T == struct)) && !NeedsHeap!(T)) {
    // Generic version.
    auto alloc = newRegionAllocator();
    alias ForeachType!(T) E;

    static if(hasLength!T) {
        auto counts = StackHash!(E, U)(max(20, data.length / 20), alloc);
    } else {
        auto counts = StackTreeAA!(E, U)(alloc);
    }
    uint N;

    foreach(elem; data)  {
        counts[elem]++;
        N++;
    }

    double ans = entropyCounts(counts.values, N);
    return ans;
}

private double entropyImpl(U, T)(T data)
if(ForeachType!(T).sizeof > 1 && NeedsHeap!(T)) {  // Generic version.
    alias ForeachType!(T) E;

    uint len = 0;
    U[E] counts;
    foreach(elem; data) {
        len++;
        counts[elem]++;
    }
    return entropyCounts(counts, len);
}

private double entropyImpl(U, T)(T data)  // byte/char specialization
if(ForeachType!(T).sizeof == 1 && !is(ForeachType!T == struct)) {
    alias ForeachType!(T) E;

    U[ubyte.max + 1] counts;

    uint min = ubyte.max, max = 0, len = 0;
    foreach(elem; data)  {
        len++;
        static if(is(E == byte)) {
            // Keep adjacent elements adjacent.  In real world use cases,
            // probably will have ranges like [-1, 1].
            ubyte e = cast(ubyte) (cast(ubyte) (elem) + byte.max);
        } else {
            ubyte e = cast(ubyte) elem;
        }
        counts[e]++;
        if(e > max) {
            max = e;
        }
        if(e < min) {
            min = e;
        }
    }

    return entropyCounts(counts.ptr[min..max + 1], len);
}

unittest {
    { // Generic version.
        int[] foo = [1, 1, 1, 2, 2, 2, 3, 3, 3];
        double entropyFoo = entropy(foo);
        assert(approxEqual(entropyFoo, log2(3)));
        int[] bar = [1, 2, 3, 1, 2, 3, 1, 2, 3];
        auto stuff = joint(foo, bar);
        double jointEntropyFooBar = entropy(joint(foo, bar));
        assert(approxEqual(jointEntropyFooBar, log2(9)));
    }
    { // byte specialization
        byte[] foo = [-1, -1, -1, 2, 2, 2, 3, 3, 3];
        double entropyFoo = entropy(foo);
        assert(approxEqual(entropyFoo, log2(3)));
        string bar = "ACTGGCTA";
        assert(entropy(bar) == 2);
    }
    { // NeedsHeap version.
        string[] arr = ["1", "1", "1", "2", "2", "2", "3", "3", "3"];
        auto m = map!("a")(arr);
        assert(approxEqual(entropy(m), log2(3)));
    }
}

/**Calculate the conditional entropy H(data | cond).*/
double condEntropy(T, U)(T data, U cond)
if(isInputRange!(T) && isInputRange!(U)) {
    static if(isForwardRange!U) {
        alias cond condForward;
    } else {
        auto alloc = newRegionAllocator();
        auto condForward = alloc.array(cond);
    }
    
    return entropy(joint(data, condForward.save)) - entropy(condForward.save);
}

unittest {
    // This shouldn't be easy to screw up.  Just really basic.
    int[] foo = [1,2,2,1,1];
    int[] bar = [1,2,3,1,2];
    assert(approxEqual(entropy(foo) - condEntropy(foo, bar),
           mutualInfo(foo, bar)));
}

private double miContingency(double observed, double expected) {
    return (observed == 0) ? 0 :
           (observed * log2(observed / expected));
}


/**Calculates the mutual information of two vectors of discrete observations.
 */
double mutualInfo(T, U)(T x, U y)
if(isInputRange!(T) && isInputRange!(U)) {
    uint xFreedom, yFreedom, n;
    typeof(return) ret;

    static if(!hasLength!T && !hasLength!U) {
        ret = toContingencyScore!(T, U, uint)
            (x, y, &miContingency, xFreedom, yFreedom, n);
    } else {
        immutable minLen = min(x.length, y.length);
        if(minLen <= ubyte.max) {
            ret = toContingencyScore!(T, U, ubyte)
                (x, y, &miContingency, xFreedom, yFreedom, n);
        } else if(minLen <= ushort.max) {
            ret = toContingencyScore!(T, U, ushort)
                (x, y, &miContingency, xFreedom, yFreedom, n);
        } else {
            ret = toContingencyScore!(T, U, uint)
                (x, y, &miContingency, xFreedom, yFreedom, n);
        }
    }

    return ret / n;
}

unittest {
    // Values from R, but converted from base e to base 2.
    assert(approxEqual(mutualInfo(bin([1,2,3,3,8].dup, 10),
           bin([8,6,7,5,3].dup, 10)), 1.921928));
    assert(approxEqual(mutualInfo(bin([1,2,1,1,3,4,3,6].dup, 2),
           bin([2,7,9,6,3,1,7,40].dup, 2)), .2935645));
    assert(approxEqual(mutualInfo(bin([1,2,1,1,3,4,3,6].dup, 4),
           bin([2,7,9,6,3,1,7,40].dup, 4)), .5435671));

}

/**
Calculates the mutual information of a contingency table representing a joint
discrete probability distribution.  Takes a set of finite forward ranges,
one for each column in the contingency table.  These can be expressed either as
a tuple of ranges or a range of ranges.
*/
double mutualInfoTable(T...)(T table) {
    // This function is really just included to give conceptual unity to
    // the infotheory module.
    return gTestContingency(table).mutualInfo;
}

/**
Calculates the conditional mutual information I(x, y | z) from a set of
observations.
*/
double condMutualInfo(T, U, V)(T x, U y, V z) {
    auto ret = entropy(joint(x, z)) - entropy(joint(x, y, z)) - entropy(z)
        + entropy(joint(y, z));
    return max(ret, 0);
}

unittest {
    // Values from Matlab mi package by Hanchuan Peng.
    auto res = condMutualInfo([1,2,1,2,1,2,1,2].dup, [3,1,2,3,4,2,1,2].dup,
                              [1,2,3,1,2,3,1,2].dup);
    assert(approxEqual(res, 0.4387));
    res = condMutualInfo([1,2,3,1,2].dup, [2,1,3,2,1].dup,
                         joint([1,1,1,2,2].dup, [2,2,2,1,1].dup));
    assert(approxEqual(res, 1.3510));
}

/**Calculates the entropy of any old input range of observations more quickly
 * than entropy(), provided that all equal values are adjacent.  If the input
 * is sorted by more than one key, i.e. structs, the result will be the joint
 * entropy of all of the keys.  The compFun alias will be used to compare
 * adjacent elements and determine how many instances of each value exist.*/
double entropySorted(alias compFun = "a == b", T)(T data)
if(isInputRange!(T)) {
    alias ElementType!(T) E;
    alias binaryFun!(compFun) comp;
    immutable n = data.length;
    immutable nrNeg1 = 1.0L / n;

    double sum = 0.0;
    int nSame = 1;
    auto last = data.front;
    data.popFront;
    foreach(elem; data) {
        if(comp(elem, last)) {
            nSame++;
        } else {
            immutable p = nSame * nrNeg1;
            nSame = 1;
            sum -= p * log2(p);
        }
        last = elem;
    }
    // Handle last run.
    immutable p = nSame * nrNeg1;
    sum -= p * log2(p);

    return sum;
}

unittest {
    uint[] foo = [1U,2,3,1,3,2,6,3,1,6,3,2,2,1,3,5,2,1].dup;
    auto sorted = foo.dup;
    sort(sorted);
    assert(approxEqual(entropySorted(sorted), entropy(foo)));
}

/**
Much faster implementations of information theory functions for the special
but common case where all observations are integers on the range [0, nBin).
This is the case, for example, when the observations have been previously
binned using, for example, dstats.base.frqBin().

Note that, due to the optimizations used, joint() cannot be used with
the member functions of this struct, except entropy().

For those looking for hard numbers, this seems to be on the order of 10x
faster than the generic implementations according to my quick and dirty
benchmarks.
*/
struct DenseInfoTheory {
    private uint nBin;

    // Saves space and makes things cache efficient by using the smallest
    // integer width necessary for binning.
    double selectSize(alias fun, T...)(T args) {
        static if(allSatisfy!(hasLength, T)) {
            immutable len = args[0].length;

            if(len <= ubyte.max) {
                return fun!ubyte(args);
            } else if(len <= ushort.max) {
                return fun!ushort(args);
            } else {
                return fun!uint(args);
            }

            // For now, assume that noone is going to have more than
            // 4 billion observations.
        } else {
            return fun!uint(args);
        }
    }

    /**
    Constructs a DenseInfoTheory object for nBin bins.  The values taken by
    each observation must then be on the interval [0, nBin).
    */
    this(uint nBin) {
        this.nBin = nBin;
    }

    /**
    Computes the entropy of a set of observations.  Note that, for this
    function, the joint() function can be used to compute joint entropies
    as long as each individual range contains only integers on [0, nBin).
    */
    double entropy(R)(R range) if(isIterable!R) {
        return selectSize!entropyImpl(range);
    }

    private double entropyImpl(Uint, R)(R range) {
        auto alloc = newRegionAllocator();
        uint n = 0;

        static if(is(typeof(range._jointRanges))) {
            // Compute joint entropy.
            immutable nRanges = range._jointRanges.length;
            auto counts = alloc.uninitializedArray!(Uint[])(nBin ^^ nRanges);
            counts[] = 0;

            Outer:
            while(true) {
                uint multiplier = 1;
                uint index = 0;

                foreach(ti, Unused; typeof(range._jointRanges)) {
                    if(range._jointRanges[ti].empty) break Outer;
                    immutable rFront = range._jointRanges[ti].front;
                    assert(rFront < nBin);  // Enforce is too costly here.

                    index += multiplier * cast(uint) rFront;
                    range._jointRanges[ti].popFront();
                    multiplier *= nBin;
                }

                counts[index]++;
                n++;
            }

            return entropyCounts(counts, n);
        } else {
            auto counts = alloc.uninitializedArray!(Uint[])(nBin);

            counts[] = 0;
            foreach(elem; range) {
                counts[elem]++;
                n++;
            }

            return entropyCounts(counts, n);
        }
    }

    /// I(x; y)
    double mutualInfo(R1, R2)(R1 x, R2 y)
    if(isIterable!R1 && isIterable!R2) {
        return selectSize!mutualInfoImpl(x, y);
    }

    private double mutualInfoImpl(Uint, R1, R2)(R1 x, R2 y) {
        auto alloc = newRegionAllocator();
        auto joint = alloc.uninitializedArray!(Uint[])(nBin * nBin);
        auto margx = alloc.uninitializedArray!(Uint[])(nBin);
        auto margy = alloc.uninitializedArray!(Uint[])(nBin);
        joint[] = 0;
        margx[] = 0;
        margy[] = 0;
        uint n;

        while(!x.empty && !y.empty) {
            immutable xFront = cast(uint) x.front;
            immutable yFront = cast(uint) y.front;
            assert(xFront < nBin);
            assert(yFront < nBin);

            joint[xFront * nBin + yFront]++;
            margx[xFront]++;
            margy[yFront]++;
            n++;
            x.popFront();
            y.popFront();
        }

        auto ret = entropyCounts(margx, n) + entropyCounts(margy, n) -
            entropyCounts(joint, n);
        return max(0, ret);
    }

    /**
    Calculates the P-value for I(X; Y) assuming x and y both have supports
    of [0, nBin).  The P-value is calculated using a Chi-Square approximation.
    It is asymptotically correct, but is approximate for finite sample size.

    Parameters:
    mutualInfo:  I(x; y), in bits
    n:  The number of samples used to calculate I(x; y)
    */
    double mutualInfoPval(double mutualInfo, double n) {
        immutable df = (nBin - 1) ^^ 2;

        immutable testStat = mutualInfo * 2 * LN2 * n;
        return chiSquareCDFR(testStat, df);
    }

    /// H(X | Y)
    double condEntropy(R1, R2)(R1 x, R2 y)
    if(isIterable!R1 && isIterable!R2) {
        return selectSize!condEntropyImpl(x, y);
    }

    private double condEntropyImpl(Uint, R1, R2)(R1 x, R2 y) {
        auto alloc = newRegionAllocator();
        auto joint = alloc.uninitializedArray!(Uint[])(nBin * nBin);
        auto margy = alloc.uninitializedArray!(Uint[])(nBin);
        joint[] = 0;
        margy[] = 0;
        uint n;

        while(!x.empty && !y.empty) {
            immutable xFront = cast(uint) x.front;
            immutable yFront = cast(uint) y.front;
            assert(xFront < nBin);
            assert(yFront < nBin);

            joint[xFront * nBin + yFront]++;
            margy[yFront]++;
            n++;
            x.popFront();
            y.popFront();
        }

        auto ret = entropyCounts(joint, n) - entropyCounts(margy, n);
        return max(0, ret);
    }

    /// I(X; Y | Z)
    double condMutualInfo(R1, R2, R3)(R1 x, R2 y, R3 z)
    if(allSatisfy!(isIterable, R1, R2, R3)) {
        return selectSize!condMutualInfoImpl(x, y, z);
    }

    private double condMutualInfoImpl(Uint, R1, R2, R3)(R1 x, R2 y, R3 z) {
        auto alloc = newRegionAllocator();
        immutable nBinSq = nBin * nBin;
        auto jointxyz = alloc.uninitializedArray!(Uint[])(nBin * nBin * nBin);
        auto jointxz = alloc.uninitializedArray!(Uint[])(nBinSq);
        auto jointyz = alloc.uninitializedArray!(Uint[])(nBinSq);
        auto margz = alloc.uninitializedArray!(Uint[])(nBin);
        jointxyz[] = 0;
        jointxz[] = 0;
        jointyz[] = 0;
        margz[] = 0;
        uint n = 0;

        while(!x.empty && !y.empty && !z.empty) {
            immutable xFront = cast(uint) x.front;
            immutable yFront = cast(uint) y.front;
            immutable zFront = cast(uint) z.front;
            assert(xFront < nBin);
            assert(yFront < nBin);
            assert(zFront < nBin);

            jointxyz[xFront * nBinSq + yFront * nBin + zFront]++;
            jointxz[xFront * nBin + zFront]++;
            jointyz[yFront * nBin + zFront]++;
            margz[zFront]++;
            n++;

            x.popFront();
            y.popFront();
            z.popFront();
        }

        auto ret = entropyCounts(jointxz, n) - entropyCounts(jointxyz, n) -
            entropyCounts(margz, n) + entropyCounts(jointyz, n);
        return max(0, ret);
    }
}

unittest {
    auto dense = DenseInfoTheory(3);
    auto a = [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2];
    auto b = [1, 2, 2, 2, 0, 0, 1, 1, 1, 1, 0, 0];
    auto c = [1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0];

    assert(entropy(a) == dense.entropy(a));
    assert(entropy(b) == dense.entropy(b));
    assert(entropy(c) == dense.entropy(c));
    assert(entropy(joint(a, c)) == dense.entropy(joint(c, a)));
    assert(entropy(joint(a, b)) == dense.entropy(joint(a, b)));
    assert(entropy(joint(c, b)) == dense.entropy(joint(c, b)));

    assert(condEntropy(a, c) == dense.condEntropy(a, c));
    assert(condEntropy(a, b) == dense.condEntropy(a, b));
    assert(condEntropy(c, b) == dense.condEntropy(c, b));

    alias approxEqual ae;
    assert(ae(mutualInfo(a, c), dense.mutualInfo(c, a)));
    assert(ae(mutualInfo(a, b), dense.mutualInfo(a, b)));
    assert(ae(mutualInfo(c, b), dense.mutualInfo(c, b)));

    assert(ae(condMutualInfo(a, b, c), dense.condMutualInfo(a, b, c)));
    assert(ae(condMutualInfo(a, c, b), dense.condMutualInfo(a, c, b)));
    assert(ae(condMutualInfo(b, c, a), dense.condMutualInfo(b, c, a)));

    // Test P-value stuff.
    immutable pDense = dense.mutualInfoPval(dense.mutualInfo(a, b), a.length);
    immutable pNotDense = gTestObs(a, b).p;
    assert(approxEqual(pDense, pNotDense));
}
