/**Hypothesis testing beyond simple CDFs.  All functions work with input
 * ranges with elements implicitly convertible to real unless otherwise noted.
 *
 * Author:  David Simcha*/
 /*
 * You may use this software under your choice of either of the following
 * licenses.  YOU NEED ONLY OBEY THE TERMS OF EXACTLY ONE OF THE TWO LICENSES.
 * IF YOU CHOOSE TO USE THE PHOBOS LICENSE, YOU DO NOT NEED TO OBEY THE TERMS OF
 * THE BSD LICENSE.  IF YOU CHOOSE TO USE THE BSD LICENSE, YOU DO NOT NEED
 * TO OBEY THE TERMS OF THE PHOBOS LICENSE.  IF YOU ARE A LAWYER LOOKING FOR
 * LOOPHOLES AND RIDICULOUSLY NON-EXISTENT AMBIGUITIES IN THE PREVIOUS STATEMENT,
 * GET A LIFE.
 *
 * ---------------------Phobos License: ---------------------------------------
 *
 *  Copyright (C) 2008-2009 by David Simcha.
 *
 *  This software is provided 'as-is', without any express or implied
 *  warranty. In no event will the authors be held liable for any damages
 *  arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute it
 *  freely, in both source and binary form, subject to the following
 *  restrictions:
 *
 *  o  The origin of this software must not be misrepresented; you must not
 *     claim that you wrote the original software. If you use this software
 *     in a product, an acknowledgment in the product documentation would be
 *     appreciated but is not required.
 *  o  Altered source versions must be plainly marked as such, and must not
 *     be misrepresented as being the original software.
 *  o  This notice may not be removed or altered from any source
 *     distribution.
 *
 * --------------------BSD License:  -----------------------------------------
 *
 * Copyright (c) 2008-2009, David Simcha
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 *     * Neither the name of the authors nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED ''AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
module dstats.tests;

import dstats.base, dstats.distrib, dstats.alloc, dstats.summary, dstats.sort,
       dstats.cor, std.algorithm, std.functional, std.range, std.c.stdlib,
       std.conv;

version(unittest) {
    import std.stdio, dstats.random;

    Random gen;

    static this() {
        gen.seed(unpredictableSeed);
    }

    void main(){}
}

/**Alternative hypotheses.  Exact meaning varies with test used.*/
enum Alt {
    /// f(input1) != X
    TWOSIDE,

    /// f(input1) < X
    LESS,

    /// f(input1) > X
    GREATER,

    /**Skip P-value computation (and confidence intervals if applicable)
     * and just return the test statistic.*/
    NONE
}

/**A plain old data struct for returning the results of hypothesis tests.*/
struct TestRes {

    /// The test statistic.  What exactly this is is specific to the test.
    real testStat;

    /**The P-value against the provided alternative.  This struct can
     * be implicitly converted to just the P-value via alias this.*/
    real p;

    /// Allow implicit conversion to the P-value.
    alias p this;

    ///
    string toString() {
        return text("Test Statistic = ", testStat, "\nP = ", p);
    }
}

/**A plain old data struct for returning the results of hypothesis tests
 * that also produce confidence intervals.  Contains, can implicitly convert
 * to, a TestRes.*/
struct ConfInt {
    ///
    TestRes testRes;

    ///  Lower bound of the confidence interval at the level specified.
    real lowerBound;

    ///  Upper bound of the confidence interval at the level specified.
    real upperBound;

    alias testRes this;

    ///
    string toString() {
        return text("Test Statistic = ", testRes.testStat, "\nP = ", testRes.p,
                "\nLower Confidence Bound = ", lowerBound,
                "\nUpper Confidence Bound = ", upperBound);
    }
}

/**One-sample Student's T-test for difference between mean of data and
 * a fixed value.  Alternatives are Alt.LESS, meaning mean(data) < testMean,
 * Alt.GREATER, meaning mean(data) > testMean, and Alt.TWOSIDE, meaning
 * mean(data)!= testMean.
 *
 * Returns:  A ConfInt containing T, the P-value and the boundaries of
 * the confidence interval for mean(T) at the level specified.*/
ConfInt studentsTTest(T)(T data, real testMean = 0, Alt alt = Alt.TWOSIDE,
    real confLevel = 0.95)
if(realIterable!(T)) {
    return pairedTTest(data, repeat(0), testMean, alt, confLevel);

}

unittest {
    auto t1 = studentsTTest([1, 2, 3, 4, 5].dup, 2);
    assert(approxEqual(t1.testStat, 1.4142));
    assert(approxEqual(t1.p, 0.2302));
    assert(approxEqual(t1.lowerBound, 1.036757));
    assert(approxEqual(t1.upperBound, 4.963243));

    auto t2 = studentsTTest([1, 2, 3, 4, 5].dup, 2, Alt.LESS);
    assert(approxEqual(t2, .8849));
    assert(approxEqual(t2.testStat, 1.4142));
    assert(t2.lowerBound == -real.infinity);
    assert(approxEqual(t2.upperBound, 4.507443));

    auto t3 = studentsTTest([1, 2, 3, 4, 5].dup, 2, Alt.GREATER);
    assert(approxEqual(t3, .1151));
    assert(approxEqual(t3.testStat, 1.4142));
    assert(approxEqual(t3.lowerBound, 1.492557));
    assert(t3.upperBound == real.infinity);

    writeln("Passed 1-sample studentsTTest test.");
}

/**Two-sample T test for a difference in means,
 * assumes variances of samples are equal.  Alteratives are Alt.LESS, meaning
 * mean(sample1) - mean(sample2) < testMean, Alt.GREATER, meaning
 * mean(sample1) - mean(sample2) > testMean, and Alt.TWOSIDE, meaning
 * mean(sample1) - mean(sample2) != testMean.
 *
 * Returns:  A ConfInt containing the T statistic, the P-value, and the
 * boundaries of the confidence interval for the difference between means
 * of sample1 and sample2 at the specified level.*/
ConfInt studentsTTest(T, U)(T sample1, U sample2, real testMean = 0,
    Alt alt = Alt.TWOSIDE, real confLevel = 0.95)
if(realIterable!(T) && realIterable!(U)) {
    size_t n1, n2;
    OnlineMeanSD s1summ, s2summ;
    foreach(elem; sample1) {
        s1summ.put(elem);
        n1++;
    }
    foreach(elem; sample2) {
        s2summ.put(elem);
        n2++;
    }

    real sx1x2 = sqrt(((n1 - 1) * s1summ.var + (n2 - 1) * s2summ.var) /
                 (n1 + n2 - 2));
    real normSd = (sx1x2 * sqrt((1.0L / n1) + (1.0L / n2)));
    real meanDiff = s1summ.mean - s2summ.mean;
    ConfInt ret;
    ret.testStat = meanDiff / normSd;
    if(alt == Alt.NONE) {
        return ret;
    } else if(alt == Alt.LESS) {
        ret.p = studentsTCDF(ret.testStat, n1 + n2 - 2);
        real delta = invStudentsTCDF(1 - confLevel, n1 + n2 - 2) * normSd;
        ret.lowerBound = -real.infinity;
        ret.upperBound = meanDiff - delta;
    } else if(alt == Alt.GREATER) {
        ret.p = studentsTCDF(-ret.testStat, n1 + n2 - 2);
        real delta = invStudentsTCDF(1 - confLevel, n1 + n2 - 2) * normSd;
        ret.lowerBound = meanDiff + delta;
        ret.upperBound = real.infinity;
    } else {
        ret.p = 2 * min(studentsTCDF(ret.testStat, n1 + n2 - 2),
                       studentsTCDF(-ret.testStat, n1 + n2 - 2));
        real delta = invStudentsTCDF(0.5 * (1 - confLevel), n1 + n2 - 2) * normSd;
        ret.lowerBound = meanDiff + delta;
        ret.upperBound = meanDiff - delta;
    }
    return ret;
}

unittest {
    // Values from R.
    auto t1 = studentsTTest([1,2,3,4,5].dup, [1,3,4,5,7,9].dup);
    assert(approxEqual(t1, 0.2346));
    assert(approxEqual(t1.testStat, -1.274));
    assert(approxEqual(t1.lowerBound, -5.088787));
    assert(approxEqual(t1.upperBound, 1.422120));


    assert(approxEqual(studentsTTest([1,2,3,4,5].dup, [1,3,4,5,7,9].dup, 0, Alt.LESS),
           0.1173));
    assert(approxEqual(studentsTTest([1,2,3,4,5].dup, [1,3,4,5,7,9].dup, 0, Alt.GREATER),
           0.8827));
    auto t2 = studentsTTest([1,3,5,7,9,11].dup, [2,2,1,3,4].dup);
    assert(approxEqual(t2, 0.06985));
    assert(approxEqual(t2.testStat, 2.0567));
    assert(approxEqual(t2.lowerBound, -0.3595529));
    assert(approxEqual(t2.upperBound, 7.5595529));


    auto t5 = studentsTTest([1,3,5,7,9,11].dup, [2,2,1,3,4].dup, 0, Alt.LESS);
    assert(approxEqual(t5, 0.965));
    assert(approxEqual(t5.testStat, 2.0567));
    assert(approxEqual(t5.upperBound, 6.80857));
    assert(t5.lowerBound == -real.infinity);

    auto t6 = studentsTTest([1,3,5,7,9,11].dup, [2,2,1,3,4].dup, 0, Alt.GREATER);
    assert(approxEqual(t6, 0.03492));
    assert(approxEqual(t6.testStat, 2.0567));
    assert(approxEqual(t6.lowerBound, 0.391422));
    assert(t6.upperBound == real.infinity);
    writeln("Passed 2-sample studentsTTest test.");
}

/**Two-sample T-test for difference in means.  Does NOT assume variances are equal.
 * Alteratives are Alt.LESS, meaning mean(sample1) - mean(sample2) < testMean,
 * Alt.GREATER, meaning mean(sample1) - mean(sample2) > testMean, and
 * Alt.TWOSIDE, meaning mean(sample1) - mean(sample2) != testMean.
 *
 * Returns:  A ConfInt containing the T statistic, the P-value, and the
 * boundaries of the confidence interval for the difference between means
 * of sample1 and sample2 at the specified level.*/
ConfInt welchTTest(T, U)(T sample1, U sample2, real testMean = 0,
    Alt alt = Alt.TWOSIDE, real confLevel = 0.95)
if(realIterable!(T) && realIterable!(U)) {
    size_t n1, n2;
    OnlineMeanSD s1summ, s2summ;
    foreach(elem; sample1) {
        s1summ.put(elem);
        n1++;
    }
    foreach(elem; sample2) {
        s2summ.put(elem);
        n2++;
    }

    auto v1 = s1summ.var, v2 = s2summ.var;
    real sx1x2 = sqrt(v1 / n1 + v2 / n2);
    real meanDiff = s1summ.mean - s2summ.mean - testMean;
    real t = meanDiff / sx1x2;
    real numerator = v1 / n1 + v2 / n2;
    numerator *= numerator;
    real denom1 = v1 / n1;
    denom1 = denom1 * denom1 / (n1 - 1);
    real denom2 = v2 / n2;
    denom2 = denom2 * denom2 / (n2 - 1);
    real df = numerator / (denom1 + denom2);

    ConfInt ret;
    ret.testStat = t;
    if(alt == Alt.NONE) {
        return ret;
    } else if(alt == Alt.LESS) {
        ret.p = studentsTCDF(t, df);
        ret.lowerBound = -real.infinity;
        ret.upperBound = meanDiff + testMean - invStudentsTCDF(1 - confLevel, df) * sx1x2;
    } else if(alt == Alt.GREATER) {
        ret.p = studentsTCDF(-t, df);
        ret.lowerBound = meanDiff + testMean + invStudentsTCDF(1 - confLevel, df) * sx1x2;
        ret.upperBound = real.infinity;
    } else {
        ret.p = 2 * min(studentsTCDF(t, df), studentsTCDF(-t, df));
        real delta = invStudentsTCDF(0.5 * (1 - confLevel), df) * sx1x2;
        ret.upperBound = meanDiff + testMean - delta;
        ret.lowerBound = meanDiff + testMean + delta;
    }
    return ret;
}

unittest {
    // Values from R.
    auto t1 = welchTTest([1,2,3,4,5].dup, [1,3,4,5,7,9].dup, 2);
    assert(approxEqual(t1, 0.02285));
    assert(approxEqual(t1.testStat, -2.8099));
    assert(approxEqual(t1.lowerBound, -4.979316));
    assert(approxEqual(t1.upperBound, 1.312649));

    auto t2 = welchTTest([1,2,3,4,5].dup, [1,3,4,5,7,9].dup, -1, Alt.LESS);
    assert(approxEqual(t2, 0.2791));
    assert(approxEqual(t2.testStat, -0.6108));
    assert(t2.lowerBound == -real.infinity);
    assert(approxEqual(t2.upperBound, 0.7035534));

    auto t3 = welchTTest([1,2,3,4,5].dup, [1,3,4,5,7,9].dup, 0.5, Alt.GREATER);
    assert(approxEqual(t3, 0.9372));
    assert(approxEqual(t3.testStat, -1.7104));
    assert(approxEqual(t3.lowerBound, -4.37022));
    assert(t3.upperBound == real.infinity);

    assert(approxEqual(welchTTest([1,3,5,7,9,11].dup, [2,2,1,3,4].dup), 0.06616));
    assert(approxEqual(welchTTest([1,3,5,7,9,11].dup, [2,2,1,3,4].dup, 0,
        Alt.LESS), 0.967));
    assert(approxEqual(welchTTest([1,3,5,7,9,11].dup, [2,2,1,3,4].dup, 0,
        Alt.GREATER), 0.03308));
    writeln("Passed welchTTest test.");
}

/**Paired T test.  Tests the hypothesis that the mean difference between
 * corresponding elements of before and after is testMean.  Alternatives are
 * Alt.LESS, meaning the that the true mean difference (before[i] - after[i])
 * is less than testMean, Alt.GREATER, meaning the true mean difference is
 * greater than testMean, and Alt.TWOSIDE, meaning the true mean difference is not
 * equal to testMean.
 *
 *
 * Returns:  A ConfInt containing the T statistic, the P-value, and the
 * boundaries of the confidence interval for the mean difference between
 * corresponding elements of sample1 and sample2 at the specified level.*/
ConfInt pairedTTest(T, U)(T before, U after, real testMean = 0,
    Alt alt = Alt.TWOSIDE, real confLevel = 0.95)
if(realInput!(T) && realInput!(U)) {
    OnlineMeanSD msd;
    size_t len = 0;
    while(!before.empty && !after.empty) {
        real diff = cast(real) before.front - cast(real) after.front;
        before.popFront;
        after.popFront;
        msd.put(diff);
        len++;
    }

    ConfInt ret;
    ret.testStat = (msd.mean - testMean) / msd.stdev * sqrt(cast(real) len);
    auto sampleMean = msd.mean;
    auto sampleSd = msd.stdev;
    real normSd = sampleSd / sqrt(cast(real) len);
    ret.testStat = (sampleMean - testMean) / normSd;

    if(alt == Alt.NONE) {
        return ret;
    } else if(alt == Alt.LESS) {
        ret.p = studentsTCDF(ret.testStat, len - 1);
        real delta = invStudentsTCDF(1 - confLevel, len - 1) * normSd;
        ret.lowerBound = -real.infinity;
        ret.upperBound = sampleMean - delta;
    } else if(alt == Alt.GREATER) {
        ret.p = studentsTCDF(-ret.testStat, len - 1);
        real delta = invStudentsTCDF(1 - confLevel, len - 1) * normSd;
        ret.lowerBound = sampleMean + delta;
        ret.upperBound = real.infinity;
    } else {
        ret.p = 2 * min(studentsTCDF(ret.testStat, len - 1),
                       studentsTCDF(-ret.testStat, len - 1));
        real delta = invStudentsTCDF(0.5 * (1 - confLevel), len - 1) * normSd;
        ret.lowerBound = sampleMean + delta;
        ret.upperBound = sampleMean - delta;
    }
    return ret;
}

unittest {
    // Values from R.
    auto t1 = pairedTTest([3,2,3,4,5].dup, [2,3,5,5,6].dup, 1);
    assert(approxEqual(t1.p, 0.02131));
    assert(approxEqual(t1.testStat, -3.6742));
    assert(approxEqual(t1.lowerBound, -2.1601748));
    assert(approxEqual(t1.upperBound, 0.561748));

    assert(approxEqual(pairedTTest([3,2,3,4,5].dup, [2,3,5,5,6].dup, 0, Alt.LESS), 0.0889));
    assert(approxEqual(pairedTTest([3,2,3,4,5].dup, [2,3,5,5,6].dup, 0, Alt.GREATER), 0.9111));
    assert(approxEqual(pairedTTest([3,2,3,4,5].dup, [2,3,5,5,6].dup, 0, Alt.TWOSIDE), 0.1778));
    assert(approxEqual(pairedTTest([3,2,3,4,5].dup, [2,3,5,5,6].dup, 1, Alt.LESS), 0.01066));
    assert(approxEqual(pairedTTest([3,2,3,4,5].dup, [2,3,5,5,6].dup, 1, Alt.GREATER), 0.9893));
    writeln("Passed pairedTTest unittest.");
}

/**The F-test is a one-way ANOVA extension of the T-test to >2 groups.
 * It's useful when you have 3 or more groups with equal variance and want
 * to test whether their means are equal.  Data can be input as either a
 * tuple of ranges (one range for each group) or a range of ranges
 * (one element for each group).
 *
 * Returns:
 * A TestRes containing the F statistic and the P-value for the alternative
 * that the means of the groups are different against the null that they
 * are identical.
 */
TestRes fTest(T...)(T dataIn)
if(allSatisfy!(isInputRange, T)) {
    static if(dataIn.length == 1 && isInputRange!(typeof(dataIn[0].front))) {
        mixin(newFrame);
        auto data = tempdup(dataIn[0]);
        auto withins = newStack!OnlineMeanSD(data.length);
        withins[] = OnlineMeanSD.init;
    } else {
        enum len = dataIn.length;
        alias dataIn data;
        OnlineMeanSD[len] withins;
    }

    OnlineMean overallMean;
    uint DFGroups = data.length - 1;
    uint DFDataPoints = 0;
    foreach(i, range; data) {
        foreach(elem; range) {
            withins[i].put(elem);
            overallMean.put(elem);
            DFDataPoints++;
        }
    }
    DFDataPoints -= data.length;
    auto mu = overallMean.mean;

    real totalWithin = 0;
    real totalBetween = 0;
    foreach(group; withins) {
        totalWithin += group.mse * (group.N / DFDataPoints);
        real diff = (group.mean - mu);
        diff *= diff;
        totalBetween += diff * (group.N / DFGroups);
    }
    auto F = totalBetween / totalWithin;
    return TestRes(F, fisherCDFR(F, DFGroups, DFDataPoints));

}

unittest {
    // Values from R.
    uint[] thing1 = [3,1,4,1], thing2 = [5,9,2,6,5,3], thing3 = [5,8,9,7,9,3];
    auto res1 = fTest(thing1, thing2, thing3);
    assert(approxEqual(res1.testStat, 4.9968));
    assert(approxEqual(res1.p, 0.02456));

    // Test array case.
    auto res2 = fTest([thing1, thing2, thing3].dup);
    assert(res1.testStat == res2.testStat);
    assert(res1.p == res2.p);

    thing1 = [2,7,1,8,2];
    thing2 = [8,1,8];
    thing3 = [2,8,4,5,9];
    auto res3 = fTest(thing1, thing2, thing3);
    assert(approxEqual(res3.testStat, 0.377));
    assert(approxEqual(res3.p, 0.6953));
    writeln("Passed fTest unittest.");
}

/**Performs a correlated sample (within-subjects) ANOVA.  This is a
 * generalization of the paired T-test to 3 or more treatments.  This
 * function accepts data as either a tuple of ranges (1 for each treatment,
 * such that a given index represents the same subject in each range) or
 * similarly as a range of ranges.
 *
 * Returns:  A TestRes with the F-statistic and P-value for the null that
 * the the variable being measured did not vary across treatments against the
 * alternative that it did.
 *
 * Examples:
 * ---
 * // Test the hypothesis that alcohol, loud music, caffeine and sleep
 * // deprivation all have equivalent effects on programming ability.
 *
 * uint[] alcohol = [8,6,7,5,3,0,9];
 * uint[] caffeine = [3,6,2,4,3,6,8];
 * uint[] noSleep = [3,1,4,1,5,9,2];
 * uint[] loudMusic = [2,7,1,8,2,8,1];
 * // Subject 0 had ability of 8 under alcohol, 3 under caffeine, 3 under
 * // no sleep, 2 under loud music.  Subject 1 had ability of 6 under alcohol,
 * // 6 under caffeine, 1 under no sleep, and 7 under loud music, etc.
 * auto result = correlatedAnova(alcohol, caffeine, noSleep, loudMusic);
 * ---
 *
 * References:  "Concepts and Applications of Inferrential Statistics".
 *              Richard Lowry.  Vassar College.  Online version.
 *              http://faculty.vassar.edu/lowry/webtext.html
 */
TestRes correlatedAnova(T...)(T dataIn)
if(allSatisfy!(isInputRange, T)) {
    static if(dataIn.length == 1 && isInputRange!(typeof(dataIn[0].front))) {
        mixin(newFrame);
        auto data = tempdup(dataIn[0]);
        auto withins = newStack!OnlineMeanSD(data.length);
        withins[] = OnlineMeanSD.init;
    } else {
        enum len = dataIn.length;
        alias dataIn data;
        OnlineMeanSD[len] withins;
    }
    OnlineMeanSD overallSumm;
    real nGroupNeg1 = 1.0L / data.length;

    bool someEmpty() {
        foreach(elem; data) {
            if(elem.empty) {
                return true;
            }
        }
        return false;
    }

    uint nSubjects = 0;
    real subjSum = 0;
    while(!someEmpty) {
        real subjSumInner = 0;
        foreach(i, elem; data) {
            auto dataPoint = elem.front;
            subjSumInner += dataPoint;
            overallSumm.put(dataPoint);
            withins[i].put(dataPoint);
            data[i].popFront;
        }
        nSubjects++;
        subjSum += subjSumInner * subjSumInner * nGroupNeg1;
    }
    real groupSum = 0;
    foreach(elem; withins) {
        groupSum += elem.mean * elem.N;
    }

    groupSum /= sqrt(cast(real) nSubjects * data.length);
    groupSum *= groupSum;
    real subjErr = subjSum - groupSum;

    real betweenDev = 0;
    real mu = overallSumm.mean;
    foreach(group; withins) {
        real diff = (group.mean - mu);
        diff *= diff;
        betweenDev += diff * (group.N / (data.length - 1));
    }

    uint errDf = data.length * nSubjects - data.length - nSubjects + 1;
    real randError = -subjErr / errDf;
    foreach(group; withins) {
        randError += group.mse * (group.N / errDf);
    }

    real F = betweenDev / randError;
    return TestRes(F, fisherCDFR(F, data.length - 1, errDf));
}

unittest {
    // Values from VassarStats utility at
    // http://faculty.vassar.edu/lowry/VassarStats.html, but they like to
    // round a lot, so the approxEqual tolerances are fairly wide.  I
    // think it's adequate to demonstrate the correctness of this function,
    // though.
    uint[] alcohol = [8,6,7,5,3,0,9];
    uint[] caffeine = [3,6,2,4,3,6,8];
    uint[] noSleep = [3,1,4,1,5,9,2];
    uint[] loudMusic = [2,7,1,8,2,8,1];
    auto result = correlatedAnova(alcohol, caffeine, noSleep, loudMusic);
    assert(approxEqual(result.testStat, 0.43, 0.0, 0.01));
    assert(approxEqual(result.p, 0.734, 0.0, 0.01));

    uint[] stuff1 = [3,4,2,6];
    uint[] stuff2 = [4,1,9,8];
    auto result2 = correlatedAnova([stuff1, stuff2].dup);
    assert(approxEqual(result2.testStat, 0.72, 0.0, 0.01));
    assert(approxEqual(result2.p, 0.4584, 0.0, 0.01));
    writeln("Passed correlatedAnova unittest.");
}

/**The Kruskal-Wallis rank sum test.  Tests the null hypothesis that data in
 * each group is not stochastically ordered with respect to data in each other
 * groups.  This is a one-way non-parametric ANOVA and can be thought of
 * as either a generalization of the Wilcoxon rank sum test to >2 groups or
 * a non-parametric equivalent to the F-test.  Data can be input as either a
 * tuple of ranges (one range for each group) or a range of ranges
 * (one element for each group).
 *
 * Bugs:  Asymptotic approximation of P-value only, not exact.  In this case,
 * I'm not sure a practical way to compute the exact P-value even exists.
 *
 * Returns:  A TestRes with the K statistic and the P-value for the null that
 * no group is stochastically larger than any other against the alternative that
 * groups are stochastically ordered.
 */
TestRes kruskalWallis(T...)(T dataIn) {
    mixin(newFrame);
    size_t N = 0;
    static if(dataIn.length == 1 && isInputRange!(typeof(dataIn[0].front))) {
        auto data = tempdup(dataIn[0]);
        alias ElementType!(typeof(data[0])) C;
        static if(dstats.base.hasLength!(typeof(data[0]))) {
            enum bool useLength = true;
        } else {
            enum bool useLength = false;
        }
    } else {
        enum len = dataIn.length;
        alias dataIn data;
        alias staticMap!(ElementType, T) Es;
        alias CommonType!(Es) C;
        static if(allSatisfy!(dstats.base.hasLength, T)) {
            enum bool useLength = true;
        } else {
            enum bool useLength = false;
        }
    }

    size_t[] lengths = newStack!size_t(data.length);
    static if(useLength) {
        foreach(i, rng; data) {
            auto rngLen = rng.length;
            lengths[i] = rngLen;
            N += rngLen;
        }
        C[] dataArray = newStack!C(N);
        size_t pos = 0;
        foreach(rng; data) {
            foreach(elem; rng) {
                dataArray[pos++] = elem;
            }
        }
    } else {
        C[] dataArray;
        //scope(exit) delete dataArray;
        auto app = appender(&dataArray);
        foreach(i, rng; data) {
            size_t oldLen = dataArray.length;
            app.put(rng);
            lengths[i] = dataArray.length - oldLen;
            N += lengths[i];
        }
    }

    float[] ranks = newStack!float(dataArray.length);
    rankSort(dataArray, ranks);

    size_t index = 0;
    real denom = 0, numer = 0;
    real rBar = 0.5L * (N + 1);
    foreach(meanI, l; lengths) {
        OnlineMean groupStats;
        foreach(i; index..index + l) {
            groupStats.put( ranks[i]);
            real diff = ranks[i] - rBar;
            diff *= diff;
            denom += diff;
        }
        index += l;
        real nDiff = groupStats.mean - rBar;
        nDiff *= nDiff;
        numer += l * nDiff;
    }
    real K = (N - 1) * (numer / denom);

    // Tie correction.
    real tieSum = 0;
    uint nTies = 1;
    foreach(i; 1..dataArray.length) {
        if(dataArray[i] == dataArray[i - 1]) {
            nTies++;
        } else if(nTies > 1) {
            real partialSum = nTies;
            partialSum = (partialSum * partialSum * partialSum) - partialSum;
            tieSum += partialSum;
            nTies = 1;
        }
    }
    if(nTies > 1) {
        real partialSum = nTies;
        partialSum = (partialSum * partialSum * partialSum) - partialSum;
        tieSum += partialSum;
    }
    real tieDenom = N;
    tieDenom = (tieDenom * tieDenom * tieDenom) - tieDenom;
    tieSum = 1 - (tieSum / tieDenom);
    K *= tieSum;
    return TestRes(K, chiSqrCDFR(K, data.length - 1));
}

unittest {
    // These values are from the VassarStat web tool at
    // http://faculty.vassar.edu/lowry/VassarStats.html .
    // R is actually wrong here because it apparently doesn't use a correction
    // for ties.
    auto res1 = kruskalWallis([3,1,4,1].dup, [5,9,2,6].dup, [5,3,5].dup);
    assert(approxEqual(res1.testStat, 4.15));
    assert(approxEqual(res1.p, 0.1256));

    // Test for other input types.
    auto res2 = kruskalWallis([[3,1,4,1].dup, [5,9,2,6].dup, [5,3,5].dup].dup);
    assert(res2 == res1);
    auto res3 = kruskalWallis(map!"a"([3,1,4,1].dup), [5,9,2,6].dup, [5,3,5].dup);
    assert(res3 == res1);
    auto res4 = kruskalWallis([map!"a"([3,1,4,1].dup),
                               map!"a"([5,9,2,6].dup),
                               map!"a"([5,3,5].dup)].dup);
    assert(res4 == res1);

    // Test w/ one more case, just with one input type.
    auto res5 = kruskalWallis([2,7,1,8,2].dup, [8,1,8,2].dup, [8,4,5,9,2].dup,
                              [7,1,8,2,8,1,8].dup);
    assert(approxEqual(res5.testStat, 1.06));
    assert(approxEqual(res5.p, 0.7867));
    writeln("Passed kruskalWallis unittest.");
}

/**The Friedman test is a non-parametric within-subject ANOVA.  It's useful
 * when parametric assumptions cannot be made.  Usage is identical to
 * correlatedAnova().
 *
 * Bugs:  No exact P-value calculation.  Asymptotic approx. only.*/
TestRes friedmanTest(T...)(T dataIn)
if(allSatisfy!(isInputRange, T)) {
    static if(dataIn.length == 1 && isInputRange!(typeof(dataIn[0].front))) {
        mixin(newFrame);
        auto data = tempdup(dataIn[0]);
        auto ranks = newStack!float(data.length);
        auto dataPoints = newStack!real(data.length);
        auto colMeans = newStack!OnlineMean(data.length);
        colMeans[] = OnlineMean.init;
    } else {
        enum len = dataIn.length;
        alias dataIn data;
        float[len] ranks;
        real[len] dataPoints;
        OnlineMean[len] colMeans;
    }
    real rBar = cast(real) data.length * (data.length + 1.0L) / 2.0L;
    OnlineMeanSD overallSumm;

    bool someEmpty() {
        foreach(elem; data) {
            if(elem.empty) {
                return true;
            }
        }
        return false;
    }

    uint N = 0;
    while(!someEmpty) {
        foreach(i, range; data) {
            dataPoints[i] = data[i].front;
            data[i].popFront;
        }
        rankSort(cast(real[]) dataPoints, cast(float[]) ranks);
        foreach(i, rank; ranks) {
            colMeans[i].put(rank);
            overallSumm.put(rank);
        }
        N++;
    }

    real between = 0;
    real mu = overallSumm.mean;
    foreach(mean; colMeans) {
        real diff = mean.mean - overallSumm.mean;
        between += diff * diff;
    }
    between *= N;
    real within = overallSumm.mse * (overallSumm.N / (overallSumm.N - N));
    real chiSq = between / within;
    real df = data.length - 1;
    return TestRes(chiSq, chiSqrCDFR(chiSq, df));
}

unittest {
    // Values from R
    uint[] alcohol = [8,6,7,5,3,0,9];
    uint[] caffeine = [3,6,2,4,3,6,8];
    uint[] noSleep = [3,1,4,1,5,9,2];
    uint[] loudMusic = [2,7,1,8,2,8,1];
    auto result = friedmanTest(alcohol, caffeine, noSleep, loudMusic);
    assert(approxEqual(result.testStat, 1.7463));
    assert(approxEqual(result.p, 0.6267));

    uint[] stuff1 = [3,4,2,6];
    uint[] stuff2 = [4,1,9,8];
    auto result2 = friedmanTest([stuff1, stuff2].dup);
    assert(approxEqual(result2.testStat, 1));
    assert(approxEqual(result2.p, 0.3173));
    writeln("Passed friedmanTest unittest.");
}

/**Computes Wilcoxon rank sum test statistic and P-value for
 * a set of observations against another set, using the given alternative.
 * Alt.LESS means that sample1 is stochastically less than sample2.
 * Alt.GREATER means sample1 is stochastically greater than sample2.
 * Alt.TWOSIDE means sample1 is stochastically less than or greater than
 * sample2.
 *
 * exactThresh is the threshold value of (n1 + n2) at which this function
 * switches from exact to approximate computation of the p-value.  Do not set
 * exactThresh to more than 200, as the exact
 * calculation is both very slow and not numerically stable past this point,
 * and the asymptotic calculation is very good for N this large.  To disable
 * exact calculation entirely, set exactThresh to 0.
 *
 * Notes:  Exact p-value computation is never used when ties are present in the
 * data, because it is not computationally feasible.
 *
 * Input ranges for this function must define a length.
 *
 * This test is also known as the Mann-Whitney U test.
 *
 * Returns:  A TestRes containing the W test statistic and the P-value against
 * the given alternative.
 */
TestRes wilcoxonRankSum(T)(T sample1, T sample2, Alt alt = Alt.TWOSIDE,
    uint exactThresh = 50) if(isInputRange!(T) && dstats.base.hasLength!(T)) {

    real tieSum;
    real W = wilcoxonRankSumW(sample1, sample2, &tieSum);
    if(alt == Alt.NONE) {
        return TestRes(W);
    }

    real p = wilcoxonRankSumPval(W, sample1.length, sample2.length, alt, tieSum,
                               exactThresh);
    return TestRes(W, p);
}

 unittest {
     // Values from R.

    assert(wilcoxonRankSum([1, 2, 3, 4, 5].dup, [2, 4, 6, 8, 10].dup).testStat == 5);
    assert(wilcoxonRankSum([2, 4, 6, 8, 10].dup, [1, 2, 3, 4, 5].dup).testStat == 20);
    assert(wilcoxonRankSum([3, 7, 21, 5, 9].dup, [2, 4, 6, 8, 10].dup).testStat == 15);

     // Simple stuff (no ties) first.  Testing approximate
     // calculation first.
     assert(approxEqual(wilcoxonRankSum([2,4,6,8,12].dup, [1,3,5,7,11,9].dup,
           Alt.TWOSIDE, 0), 0.9273));
     assert(approxEqual(wilcoxonRankSum([2,4,6,8,12].dup, [1,3,5,7,11,9].dup,
           Alt.LESS, 0), 0.6079));
     assert(approxEqual(wilcoxonRankSum([2,4,6,8,12].dup, [1,3,5,7,11,9].dup,
           Alt.GREATER, 0), 0.4636));
     assert(approxEqual(wilcoxonRankSum([1,2,6,10,12].dup, [3,5,7,8,13,15].dup,
            Alt.TWOSIDE, 0), 0.4113));
     assert(approxEqual(wilcoxonRankSum([1,2,6,10,12].dup, [3,5,7,8,13,15].dup,
            Alt.LESS, 0), 0.2057));
     assert(approxEqual(wilcoxonRankSum([1,2,6,10,12].dup, [3,5,7,8,13,15].dup,
            Alt.GREATER, 0), 0.8423));
     assert(approxEqual(wilcoxonRankSum([1,3,5,7,9].dup, [2,4,6,8,10].dup,
            Alt.TWOSIDE, 0), .6745));
     assert(approxEqual(wilcoxonRankSum([1,3,5,7,9].dup, [2,4,6,8,10].dup,
            Alt.LESS, 0), .3372));
     assert(approxEqual(wilcoxonRankSum([1,3,5,7,9].dup, [2,4,6,8,10].dup,
            Alt.GREATER, 0), .7346));

    // Now, lots of ties.
    assert(approxEqual(wilcoxonRankSum([1,2,3,4,5].dup, [2,3,4,5,6].dup,
           Alt.TWOSIDE, 0), 0.3976));
    assert(approxEqual(wilcoxonRankSum([1,2,3,4,5].dup, [2,3,4,5,6].dup,
           Alt.LESS, 0), 0.1988));
    assert(approxEqual(wilcoxonRankSum([1,2,3,4,5].dup, [2,3,4,5,6].dup,
           Alt.GREATER, 0), 0.8548));
    assert(approxEqual(wilcoxonRankSum([1,2,1,1,2].dup, [1,2,3,1,1].dup,
           Alt.TWOSIDE, 0), 0.9049));
    assert(approxEqual(wilcoxonRankSum([1,2,1,1,2].dup, [1,2,3,1,1].dup,
           Alt.LESS, 0), 0.4524));
    assert(approxEqual(wilcoxonRankSum([1,2,1,1,2].dup, [1,2,3,1,1].dup,
           Alt.GREATER, 0), 0.64));

    // Now, testing the exact calculation on the same data.
     assert(approxEqual(wilcoxonRankSum([2,4,6,8,12].dup, [1,3,5,7,11,9].dup,
       Alt.TWOSIDE), 0.9307));
     assert(approxEqual(wilcoxonRankSum([2,4,6,8,12].dup, [1,3,5,7,11,9].dup,
           Alt.LESS), 0.6039));
     assert(approxEqual(wilcoxonRankSum([2,4,6,8,12].dup, [1,3,5,7,11,9].dup,
           Alt.GREATER), 0.4654));
     assert(approxEqual(wilcoxonRankSum([1,2,6,10,12].dup, [3,5,7,8,13,15].dup,
            Alt.TWOSIDE), 0.4286));
     assert(approxEqual(wilcoxonRankSum([1,2,6,10,12].dup, [3,5,7,8,13,15].dup,
            Alt.LESS), 0.2143));
     assert(approxEqual(wilcoxonRankSum([1,2,6,10,12].dup, [3,5,7,8,13,15].dup,
            Alt.GREATER), 0.8355));
     assert(approxEqual(wilcoxonRankSum([1,3,5,7,9].dup, [2,4,6,8,10].dup,
            Alt.TWOSIDE), .6905));
     assert(approxEqual(wilcoxonRankSum([1,3,5,7,9].dup, [2,4,6,8,10].dup,
            Alt.LESS), .3452));
     assert(approxEqual(wilcoxonRankSum([1,3,5,7,9].dup, [2,4,6,8,10].dup,
            Alt.GREATER), .7262));
    writeln("Passed wilcoxonRankSum test.");
}

real wilcoxonRankSumW(T)(T sample1, T sample2, real* tieSum = null)
if(isInputRange!(T) && dstats.base.hasLength!(T)) {
    ulong n1 = sample1.length, n2 = sample2.length, N = n1 + n2;
    auto combined = newStack!(Unqual!(ElementType!(T)))(N);
    rangeCopy(combined[0..n1], sample1);
    rangeCopy(combined[n1..$], sample2);

    float[] ranks = newStack!(float)(N);
    rankSort(combined, ranks);
    real w = reduce!("a + b")(0.0L, ranks[0..n1]) - n1 * (n1 + 1) / 2UL;
    TempAlloc.free;  // Free ranks.

    if(tieSum !is null) {
        // combined is sorted by rankSort.  Can use it to figure out how many
        // ties we have w/o another allocation or sorting.
        enum oneOverTwelve = 1.0L / 12.0L;
        *tieSum = 0;
        ulong nties = 1;
        foreach(i; 1..N) {
            if(combined[i] == combined[i - 1]) {
                nties++;
            } else {
                if(nties == 1)
                    continue;
                *tieSum += ((nties * nties * nties) - nties) * oneOverTwelve;
                nties = 1;
            }
        }
        // Handle last run.
        if(nties > 1) {
            *tieSum += ((nties * nties * nties) - nties) * oneOverTwelve;
        }
    }
    TempAlloc.free;  // Free combined.
    return w;
}

real wilcoxonRankSumPval(T)(T w, ulong n1, ulong n2, Alt alt = Alt.TWOSIDE,
                           real tieSum = 0,  uint exactThresh = 50) {
    ulong N = n1 + n2;

    if(N < exactThresh && tieSum == 0) {
        return wilcoxRSPExact(cast(uint) w, n1, n2, alt);
    }

    real sd = sqrt(cast(real) (n1 * n2) / (N * (N - 1)) *
             ((N * N * N - N) / 12 - tieSum));
    real mean = (n1 * n2) / 2.0L;
    if(alt == Alt.TWOSIDE)
        return 2.0L * min(normalCDF(w + .5, mean, sd),
                          normalCDFR(w - .5, mean, sd), 0.5L);
    else if(alt == Alt.LESS)
        return normalCDF(w + .5, mean, sd);
    else if(alt == Alt.GREATER)
        return normalCDFR(w - .5, mean, sd);
}

unittest {
    /* Values from R.  I could only get good values for Alt.LESS directly.
     * Using W-values to test Alt.TWOSIDE, Alt.GREATER indirectly.*/
    assert(approxEqual(wilcoxonRankSumPval(1200, 50, 50, Alt.LESS), .3670));
    assert(approxEqual(wilcoxonRankSumPval(1500, 50, 50, Alt.LESS), .957903));
    assert(approxEqual(wilcoxonRankSumPval(8500, 100, 200, Alt.LESS), .01704));
    auto w = wilcoxonRankSumW([2,4,6,8,12].dup, [1,3,5,7,11,9].dup);
    assert(approxEqual(wilcoxonRankSumPval(w, 5, 6), 0.9273));
    assert(approxEqual(wilcoxonRankSumPval(w, 5, 6, Alt.GREATER), 0.4636));
    assert(approxEqual(wilcoxonRankSumPval(w, 5, 6, Alt.LESS), 0.6079));
}

/* Used internally by wilcoxonRankSum.  This function uses dynamic
 * programming to count the number of combinations of numbers [1..N] that sum
 * of length n1 that sum to <= W in O(N * W * n1) time.*/
real wilcoxRSPExact(uint W, uint n1, uint n2, Alt alt = Alt.TWOSIDE) {
    uint N = n1 + n2;
    uint expected2 = n1 * n2;
    switch(alt) {
        case Alt.LESS:
            if(W > (N * (N - n2)) / 2)  { // Value impossibly large
                return 1;
            } else if(W * 2 <= expected2) {
                break;
            } else {
                return 1 - wilcoxRSPExact(expected2 - W - 1, n1, n2, Alt.LESS);
            }
        case Alt.GREATER:
            if(W > (N * (N - n2)) / 2)  { // Value impossibly large
                return 0;
            } else if(W * 2 >= expected2) {
                return wilcoxRSPExact(expected2 - W, n1, n2, Alt.LESS);
            } else {
                return 1 - wilcoxRSPExact(W - 1, n1, n2, Alt.LESS);
            }
        case Alt.TWOSIDE:
            if(W * 2 <= expected2) {
                return min(1, wilcoxRSPExact(W, n1, n2, Alt.LESS) +
                       wilcoxRSPExact(expected2 - W, n1, n2, Alt.GREATER));
            } else {
                return min(1, wilcoxRSPExact(W, n1, n2, Alt.GREATER) +
                       wilcoxRSPExact(expected2 - W, n1, n2, Alt.LESS));
            }
        default:
            assert(0);
    }

    W += n1 * (n1 + 1) / 2UL;

    float* cache = (newStack!(float)((n1 + 1) * (W + 1))).ptr;
    float* cachePrev = (newStack!(float)((n1 + 1) * (W + 1))).ptr;
    cache[0..(n1 + 1) * (W + 1)] = 0;
    cachePrev[0..(n1 + 1) * (W + 1)] = 0;

    /* Using reals for the intermediate steps is too slow, but I didn't want to
     * lose too much precision.  Since my sums must be between 0 and 1, I am
     * using the entire bit space of a float to hold numbers between zero and
     * one.  This is precise to at least 1e-7.  This is good enough for a few
     * reasons:
     *
     * 1.  This is a p-value, and therefore will likely not be used in
     *     further calculations where rounding error would accumulate.
     * 2.  If this is too slow, the alternative is to use the asymptotic
     *     approximation.  This is can have relative errors of several orders
     *     of magnitude in the tails of the distribution, and is therefore
     *     clearly worse.
     * 3.  For very large N, where this function could give completely wrong
     *     answers, it would be so slow that any reasonable person would use the
     *     asymptotic approximation anyhow.*/

    real comb = exp(-logNcomb(N, n1));
    real floatMax = cast(real) float.max;
    cache[0] = cast(float) (comb * floatMax);
    cachePrev[0] = cast(float) (comb * floatMax);

    foreach(i; 1..N + 1) {
        swap(cache, cachePrev);
        foreach(k; 1..min(i + 1, n1 + 1)) {

            uint minW = k * (k + 1) / 2;
            float* curK = cache + k * (W + 1);
            float* prevK = cachePrev + k * (W + 1);
            float* prevKm1 = cachePrev + (k - 1) * (W + 1);

            foreach(w; minW..W + 1) {
                curK[w] = prevK[w] + ((i <= w) ? prevKm1[w - i] : 0);
            }
        }
    }

    real sum = 0;
    float* lastLine = cache + n1 * (W + 1);
    foreach(w; 1..W + 1) {
        sum += (cast(real) lastLine[w] / floatMax);
    }
    TempAlloc.free;
    TempAlloc.free;
    return sum;
}

unittest {
    // Values from R.
    assert(approxEqual(wilcoxRSPExact(14, 5, 6), 0.9307));
    assert(approxEqual(wilcoxRSPExact(14, 5, 6, Alt.LESS), 0.4654));
    assert(approxEqual(wilcoxRSPExact(14, 5, 6, Alt.GREATER), 0.6039));
    assert(approxEqual(wilcoxRSPExact(16, 6, 5), 0.9307));
    assert(approxEqual(wilcoxRSPExact(16, 6, 5, Alt.LESS), 0.6039));
    assert(approxEqual(wilcoxRSPExact(16, 6, 5, Alt.GREATER), 0.4654));

    // Mostly to make sure that underflow doesn't happen until
    // the N's are truly unreasonable:
    //assert(approxEqual(wilcoxRSPExact(6_000, 120, 120, Alt.LESS), 0.01276508));
}

/**Computes a test statistic and P-value for a Wilcoxon signed rank test against
 * the given alternative. Alt.LESS means that elements of before are stochastically
 * less than corresponding elements of after.  Alt.GREATER means elements of
 * before are stochastically greater than corresponding elements of after.
 * Alt.TWOSIDE means there is a significant difference in either direction.
 *
 * exactThresh is the threshold value of before.length at which this function
 * switches from exact to approximate computation of the p-value.   Do not set
 * exactThresh to more than 200, as the exact calculation is both very slow and
 * not numerically stable past this point, and the asymptotic calculation is
 * very good for N this large.  To disable exact calculation entirely, set
 * exactThresh to 0.
 *
 * Notes:  Exact p-value computation is never used when ties are present,
 * because it is not computationally feasible.
 *
 * The input ranges for this function must define a length and must be
 * forward ranges.
 *
 * Returns:  A TestRes of the W statistic and the p-value against the given
 * alternative.*/
TestRes wilcoxonSignedRank(T, U)(T before, U after, Alt alt = Alt.TWOSIDE, uint exactThresh = 50)
if(realInput!(T) && dstats.base.hasLength!(T) && isForwardRange!(T)  &&
 realInput!(U) && dstats.base.hasLength!(U) && isForwardRange!(U))
in {
    assert(before.length == after.length);
} body {
    ulong N = before.length;

    mixin(newFrame);
    float[] diffRanks = newStack!(float)(before.length);
    byte[] signs = newStack!(byte)(before.length);
    real[] diffs = newStack!(real)(before.length);
    uint nZero = 0;

    byte sign(real input) {
        if(input < 0)
            return -1;
        if(input > 0)
            return 1;
        N--;
        nZero++;
        return 0;
    }

    size_t ii = 0;
    while(!before.empty && !after.empty) {
        real diff = cast(real) before.front - cast(real) after.front;
        signs[ii] = sign(diff);
        diffs[ii] = abs(diff);
        ii++;
        before.popFront;
        after.popFront;
    }
    rankSort(diffs, diffRanks);

    real W = 0;
    foreach(i, dr; diffRanks) {
        if(signs[i] == 1) {
            W += dr - nZero;
        }
    }

    if(alt == Alt.NONE) {
        return TestRes(W);
    }

    // Handle ties.
    real tieSum = 0;

    // combined is sorted by rankSort.  Can use it to figure out how many
    // ties we have w/o another allocation or sorting.
    enum denom = 1.0L / 48.0L;
    ulong nties = 1;
    foreach(i; 1..diffs.length) {
        if(diffs[i] == diffs[i - 1] && diffs[i] != 0) {
            nties++;
        } else {
            if(nties == 1)
                continue;
            tieSum += ((nties * nties * nties) - nties) * denom;
            nties = 1;
        }
    }
    // Handle last run.
    if(nties > 1) {
        tieSum += ((nties * nties * nties) - nties) * denom;
    }
    if(nZero > 0 && tieSum == 0) {
        tieSum = real.nan;  // Signal that there were zeros and exact p-val can't be computed.
    }

    return TestRes(W, wilcoxonSignedRankPval(W, N, alt, tieSum, exactThresh));
}

unittest {
    // Values from R.
    alias approxEqual ae;
    assert(wilcoxonSignedRank([1,2,3,4,5].dup, [2,1,4,5,3].dup).testStat == 7.5);
    assert(wilcoxonSignedRank([3,1,4,1,5].dup, [2,7,1,8,2].dup).testStat == 6);
    assert(wilcoxonSignedRank([8,6,7,5,3].dup, [0,9,8,6,7].dup).testStat == 5);

    // With ties, normal approx.
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,1,4,5,3].dup), 1));
    assert(ae(wilcoxonSignedRank([3,1,4,1,5].dup, [2,7,1,8,2].dup), 0.7865));
    assert(ae(wilcoxonSignedRank([8,6,7,5,3].dup, [0,9,8,6,7].dup), 0.5879));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,1,4,5,3].dup, Alt.LESS), 0.5562));
    assert(ae(wilcoxonSignedRank([3,1,4,1,5].dup, [2,7,1,8,2].dup, Alt.LESS), 0.3932));
    assert(ae(wilcoxonSignedRank([8,6,7,5,3].dup, [0,9,8,6,7].dup, Alt.LESS), 0.2940));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,1,4,5,3].dup, Alt.GREATER), 0.5562));
    assert(ae(wilcoxonSignedRank([3,1,4,1,5].dup, [2,7,1,8,2].dup, Alt.GREATER), 0.706));
    assert(ae(wilcoxonSignedRank([8,6,7,5,3].dup, [0,9,8,6,7].dup, Alt.GREATER), 0.7918));
    assert(ae(wilcoxonSignedRank(cast(int[]) [1,16,2,4,8], cast(int[]) [1,5,2,3,4]).testStat, 6));
    assert(ae(wilcoxonSignedRank(cast(int[]) [1,16,2,4,8], cast(int[]) [1,5,2,3,4]), 0.1814));

    // Exact.
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,-4,-8,16,32].dup), 0.625));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,-4,-8,16,32].dup, Alt.LESS), 0.3125));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,-4,-8,16,32].dup, Alt.GREATER), 0.7812));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,-4,-8,-16,32].dup), 0.8125));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,-4,-8,-16,32].dup, Alt.LESS), 0.6875));
    assert(ae(wilcoxonSignedRank([1,2,3,4,5].dup, [2,-4,-8,-16,32].dup, Alt.GREATER), 0.4062));
}

/**Same as the overload, but allows testing whether a range is stochastically
 * less than or greater than a fixed value mu rather than paired elements of
 * a second range.*/
TestRes wilcoxonSignedRank(T)(T data, real mu, Alt alt = Alt.TWOSIDE, uint exactThresh = 50)
if(realInput!(T) && dstats.base.hasLength!(T) && isForwardRange!(T)) {
    return wilcoxonSignedRank(data, take(data.length, repeat(mu)), alt, exactThresh);
}

unittest {
    auto res = wilcoxonSignedRank([-8,-6,2,4,7].dup, 0);
    assert(approxEqual(res.testStat, 7));
    assert(approxEqual(res.p, 1));
    writeln("Passed wilcoxonSignedRank unittest.");
}


real wilcoxonSignedRankPval(T)(T W, ulong N, Alt alt = Alt.TWOSIDE,
     real tieSum = 0, uint exactThresh = 50)
in {
    assert(N > 0);
    assert(tieSum >= 0 || isNaN(tieSum));
} body {
    if(tieSum == 0 && !isNaN(tieSum) && N <= exactThresh) {
        return wilcoxSRPExact(cast(uint) W, N, alt);
    }

    if(isNaN(tieSum)) {
        tieSum = 0;
    }

    real expected = N * (N + 1) * 0.25L;
    real sd = sqrt(N * (N + 1) * (2 * N + 1) / 24.0L - tieSum);

    if(alt == Alt.LESS) {
        return normalCDF(W + 0.5, expected, sd);
    } else if(alt == Alt.GREATER) {
        return normalCDFR(W - 0.5, expected, sd);
    } else {
        return 2 * min(normalCDF(W + 0.5, expected, sd),
                       normalCDFR(W - 0.5, expected, sd), 0.5L);
    }
}
// Tested indirectly through other overload.

/* Yes, a little cut and paste coding was involved here from wilcoxRSPExact,
 * but this function and wilcoxRSPExact are just different enough that
 * it would be more trouble than it's worth to write one generalized
 * function.*/
real wilcoxSRPExact(uint W, uint N, Alt alt = Alt.TWOSIDE) {
    uint expected2 = N * (N + 1) / 2;
    switch(alt) {
        case Alt.LESS:
            if(W > (N * (N + 1) / 2))  { // Value impossibly large
                return 1;
            } else if(W * 2 <= expected2) {
                break;
            } else {
                return 1 - wilcoxSRPExact(expected2 - W - 1, N, Alt.LESS);
            }
        case Alt.GREATER:
            if(W > (N * (N + 1) / 2))  { // Value impossibly large
                return 0;
            } else if(W * 2 >= expected2) {
                return wilcoxSRPExact(expected2 - W, N, Alt.LESS);
            } else {
                return 1 - wilcoxSRPExact(W - 1, N, Alt.LESS);
            }
        case Alt.TWOSIDE:
            if(W * 2 <= expected2) {
                return min(1, wilcoxSRPExact(W, N, Alt.LESS) +
                       wilcoxSRPExact(expected2 - W, N, Alt.GREATER));
            } else {
                return min(1, wilcoxSRPExact(W, N, Alt.GREATER) +
                       wilcoxSRPExact(expected2 - W, N, Alt.LESS));
            }
        default:
            assert(0);
    }

    float* cache = (newStack!(float)((N + 1) * (W + 1))).ptr;
    float* cachePrev = (newStack!(float)((N + 1) * (W + 1))).ptr;
    cache[0..(N + 1) * (W + 1)] = 0;
    cachePrev[0..(N + 1) * (W + 1)] = 0;

    real comb = pow(2.0L, -(cast(real) N));
    real floatMax = cast(real) float.max;
    cache[0] = cast(float) (comb * floatMax);
    cachePrev[0] = cast(float) (comb * floatMax);

    foreach(i; 1..N + 1) {
        swap(cache, cachePrev);
        foreach(k; 1..i + 1) {

            uint minW = k * (k + 1) / 2;
            float* curK = cache + k * (W + 1);
            float* prevK = cachePrev + k * (W + 1);
            float* prevKm1 = cachePrev + (k - 1) * (W + 1);

            foreach(w; minW..W + 1) {
                curK[w] = prevK[w] + ((i <= w) ? prevKm1[w - i] : 0);
            }
        }
    }

    real sum  = 0;
    foreach(elem; cache[0..(N + 1) * (W + 1)]) {
        sum += cast(real) elem / (cast(real) float.max);
    }
    TempAlloc.free;
    TempAlloc.free;
    return sum;
}

unittest {
    // Values from R.
    assert(approxEqual(wilcoxSRPExact(25, 10, Alt.LESS), 0.4229));
    assert(approxEqual(wilcoxSRPExact(25, 10, Alt.GREATER), 0.6152));
    assert(approxEqual(wilcoxSRPExact(25, 10, Alt.TWOSIDE), 0.8457));
    assert(approxEqual(wilcoxSRPExact(31, 10, Alt.LESS), 0.6523));
    assert(approxEqual(wilcoxSRPExact(31, 10, Alt.GREATER), 0.3848));
    assert(approxEqual(wilcoxSRPExact(31, 10, Alt.TWOSIDE), 0.7695));
    writeln("Passed wilcoxSRPExact unittest.");
}

/**Sign test for differences between paired values.  This is a very robust
 * but very low power test.  Alternatives are Alt.LESS, meaning elements
 * of before are typically less than corresponding elements of after,
 * Alt.GREATER, meaning elements of before are typically greater than
 * elements of after, and Alt.TWOSIDE, meaning that there is a significant
 * difference in either direction.
 *
 * Returns:  A TestRes with the proportion of elements of before that were
 * greater than the corresponding element of after, and the P-value against
 * the given alternative.*/
TestRes signTest(T, U)(T before, U after, Alt alt = Alt.TWOSIDE)
if(realInput!(T) && realInput!(U)) {
    uint greater, less;
    while(!before.empty && !after.empty) {
        if(before.front < after.front)
            less++;
        else if(after.front < before.front)
            greater++;
        // Ignore equals.
        before.popFront;
        after.popFront;
    }
    real propGreater = cast(real) greater / (greater + less);
    if(alt == Alt.NONE) {
        return TestRes(propGreater);
    } else if(alt == Alt.LESS) {
        return TestRes(propGreater, binomialCDF(greater, less + greater, 0.5));
    } else if(alt == Alt.GREATER) {
        return TestRes(propGreater, binomialCDF(less, less + greater, 0.5));
    } else if(less > greater) {
        return TestRes(propGreater, 2 * binomialCDF(greater, less + greater, 0.5));
    } else if(greater > less) {
        return  TestRes(propGreater, 2 * binomialCDF(less, less + greater, 0.5));
    } else return TestRes(propGreater, 1);
}

unittest {
    alias approxEqual ae;
    assert(ae(signTest([1,3,4,2,5].dup, [1,2,4,8,16].dup), 1));
    assert(ae(signTest([1,3,4,2,5].dup, [1,2,4,8,16].dup, Alt.LESS), 0.5));
    assert(ae(signTest([1,3,4,2,5].dup, [1,2,4,8,16].dup, Alt.GREATER), 0.875));
    assert(ae(signTest([5,3,4,6,8].dup, [1,2,3,4,5].dup, Alt.GREATER), 0.03125));
    assert(ae(signTest([5,3,4,6,8].dup, [1,2,3,4,5].dup, Alt.LESS), 1));
    assert(ae(signTest([5,3,4,6,8].dup, [1,2,3,4,5].dup), 0.0625));

    assert(approxEqual(signTest([1,2,6,7,9].dup, 2), 0.625));
    assert(ae(signTest([1,2,6,7,9].dup, 2).testStat, 0.75));
    writeln("Passed signTest unittest.");
}

/**Similar to the overload, but allows testing for a difference between a
 * range and a fixed value mu.*/
TestRes signTest(T)(T data, real mu, Alt alt = Alt.TWOSIDE)
if(realInput!(T)) {
    return signTest(data, repeat(mu), alt);
}

/**Two-sided binomial test for whether P(success) == p.  The one-sided
 * alternatives are covered by dstats.distrib.binomialCDF and binomialCDFR.
 * k is the number of successes observed, n is the number of trials, p
 * is the probability of success under the null.
 *
 * Returns:  The P-value for the alternative that P(success) != p against
 * the null that P(success) == p.
 *
 * Notes:  This test can also be performed using multinomialTest(), but this
 * implementation is much faster and easier to use.
 */
real binomialTest(uint k, uint n, real p) {
    immutable mode = cast(uint) ((n + 1) * p);
    if(k == mode ||
       approxEqual(binomialPMF(k, n, p), binomialPMF(mode, n, p), 1e-7)) {
        return 1;
    } else if(k > mode) {
        immutable upperPart = binomialCDFR(k, n, p);
        immutable pExact = binomialPMF(k, n, p);
        uint ulim = mode, llim = 0, guess;
        while(ulim - llim > 1) {
            // Not worrying about overflow b/c for values that large, there
            // are probably bigger numerical stability issues, etc. anyhow.
            guess = (ulim + llim) / 2;
            real pGuess = binomialPMF(guess, n, p);

            if(approxEqual(pGuess, pExact, 1e-7)) {
                ulim = guess;
                llim = guess;
                break;
            } else if(pGuess < pExact) {
                llim = guess;
            } else {
                ulim = guess;
            }
        }
        guess = (binomialPMF(ulim, n, p) > pExact) ? llim : ulim;
        if(guess == 0 && binomialPMF(0, n, p) > pExact) {
            return upperPart;
        }
        return upperPart + binomialCDF(guess, n, p);
    } else {
        real myPMF(uint k, uint n, real p) {
            return k > n ? 0 : binomialPMF(k, n, p);
        }
        immutable lowerPart = binomialCDF(k, n, p);
        immutable pExact = binomialPMF(k, n, p);
        uint ulim = n + 1, llim = mode, guess;
        while(ulim - llim > 1) {
            // Not worrying about overflow b/c for values that large, there
            // are probably bigger numerical stability issues, etc. anyhow.
            guess = (ulim + llim) / 2;
            real pGuess = myPMF(guess, n, p);
            if(approxEqual(pGuess, pExact, 1e-7)) {
                ulim = guess;
                llim = guess;
                break;
            } else if(pGuess < pExact) {
                ulim = guess;
            } else {
                llim = guess;
            }
        }
        guess = (myPMF(llim, n, p) > pExact) ? ulim : llim;
        return lowerPart + ((guess > n) ? 0 : binomialCDFR(guess, n, p));
    }
}

unittest {
    // Values from R.
    assert(approxEqual(binomialTest(6, 88, 0.1), 0.3784));
    assert(approxEqual(binomialTest(3, 4, 0.5), 0.625));
    assert(approxEqual(binomialTest(4, 7, 0.8), 0.1480));
    assert(approxEqual(binomialTest(3, 9, 0.8), 0.003066));
    assert(approxEqual(binomialTest(9, 9, 0.7), 0.06565));
    assert(approxEqual(binomialTest(2, 11, 0.1), 0.3026));
    assert(approxEqual(binomialTest(1, 11, 0.1), 1));
    assert(approxEqual(binomialTest(5, 11, 0.1), 0.002751));
    assert(approxEqual(binomialTest(5, 12, 0.5), 0.7744));
    assert(approxEqual(binomialTest(12, 12, 0.5), 0.0004883));
    assert(approxEqual(binomialTest(12, 13, 0.6), 0.02042));
    assert(approxEqual(binomialTest(0, 9, 0.1), 1));
    writeln("Passed binomialTest test.");
}

///For chiSqrFit and gTestFit, is expected value range counts or proportions?
enum Expected {
    ///
    COUNT,

    ///
    PROPORTION
}

/**Performs a one-way Pearson's chi-square goodness of fit test between a range
 * of observed and a range of expected values.  This is a useful statistical
 * test for testing whether a set of observations fits a discrete distribution.
 *
 * Returns:  A TestRes of the chi-square statistic and the P-value for the
 * alternative hypothesis that observed is not a sample from expected against
 * the null that observed is a sample from expected.
 *
 * Notes:  By default, expected is assumed to be a range of expected proportions.
 * These proportions are automatically normalized, and can sum to any number.
 * By passing Expected.COUNT in as the last parameter, calculating expected
 * counts will be skipped, and expected will assume to already be properly
 * normalized.  This is slightly faster, but more importantly
 * allows input ranges to be used.
 *
 * The chi-square test relies on asymptotic statistical properties
 * and is therefore not considered valid, as a rule of thumb,  when expected
 * counts are below 5.  However, this rule is likely to be unnecessarily
 * stringent in most cases.
 *
 * This is, for all practical purposes, an inherently non-directional test.
 * Therefore, the one-sided verses two-sided option is not provided.
 *
 * Examples:
 * ---
 * // Test to see whether a set of categorical observations differs
 * // statistically from a discrete uniform distribution.
 *
 * uint[] observed = [980, 1028, 1001, 964, 1102];
 * auto expected = repeat(1.0L);
 * auto res2 = chiSqrFit(observed, expected);
 * assert(approxEqual(res2, 0.0207));
 * assert(approxEqual(res2.testStat, 11.59));
 * ---
 */
TestRes chiSqrFit(T, U)(T observed, U expected, Expected countProp = Expected.PROPORTION) {
    return goodnessFit!(pearsonChiSqElem, T, U)(observed, expected, countProp);
}

unittest {
    // Test to see whether a set of categorical observations differs
    // statistically from a discrete uniform distribution.
    uint[] observed = [980, 1028, 1001, 964, 1102];
    auto expected = repeat(cast(real) sum(observed) / observed.length);
    auto res = chiSqrFit(observed, expected, Expected.COUNT);
    assert(approxEqual(res, 0.0207));
    assert(approxEqual(res.testStat, 11.59));

    expected = repeat(5.0L);
    auto res2 = chiSqrFit(observed, expected);
    assert(approxEqual(res2, 0.0207));
    assert(approxEqual(res2.testStat, 11.59));
    writeln("Passed chiSqrFit test.");
}

/**The G or likelihood ratio chi-square test for goodness of fit.  Roughly
 * the same as Pearson's chi-square test (chiSqrFit), but may be more
 * accurate in certain situations and less accurate in others.  However, it is
 * still based on asymptotic distributions, and is not exact. Usage is is
 * identical to chiSqrFit.
 */
TestRes gTestFit(T, U)(T observed, U expected, Expected countProp = Expected.PROPORTION) {
    return goodnessFit!(gTestElem, T, U)(observed, expected, countProp);
}
// No unittest because I can't find anything to test this against.  However,
// it's hard to imagine how it could be wrong, given that goodnessFit() and
// gTestElem() both work, and, as expected, this function produces roughly
// the same results as chiSqrFit.

private TestRes goodnessFit(alias elemFun, T, U)(T observed, U expected, Expected countProp)
if(realInput!(T) && realInput!(U))
in {
    if(countProp == Expected.COUNT) {
        assert(isForwardRange!(U));
    }
} body {
    uint len = 0;
    real chiSq = 0;
    real multiplier = 1;

    if(countProp == Expected.PROPORTION) {
        real expectSum = 0;
        multiplier = 0;
        auto obsCopy = observed;
        auto expCopy = expected;
        while(!obsCopy.empty && !expCopy.empty) {
            multiplier += obsCopy.front;
            expectSum += expCopy.front;
            obsCopy.popFront;
            expCopy.popFront;
        }
        multiplier /= expectSum;
    }

    while(!observed.empty && !expected.empty) {
        real e = expected.front * multiplier;
        chiSq += elemFun(observed.front, e);
        observed.popFront;
        expected.popFront;
        len++;
    }
    return TestRes(chiSq, chiSqrCDFR(chiSq, len - 1));
}

/**The exact multinomial goodness of fit test for whether a set of counts
 * fits a hypothetical distribution.  counts is an input range of counts.
 * proportions is an input range of expected proportions.  These are normalized
 * automatically, so they can sum to any value.
 *
 * Returns:  The P-value for the null that counts is a sample from proportions
 * against the alternative that it isn't.
 *
 * Notes:  This test is EXTREMELY slow for anything but very small samples and
 * degrees of freedom.  The Pearson's chi-square (chiSqrFit()) or likelihood
 * ratio chi-square (gTestFit()) are good enough approximations unless sample
 * size is very small.
 */
real multinomialTest(U, F)(U counts, F proportions)
if(isInputRange!U && isInputRange!F &&
   isIntegral!(ElementType!U) && isFloatingPoint!(ElementType!(F))) {
    mixin(newFrame);
    uint N = sum(counts);

    real[] logPs;
    static if(std.range.hasLength!F) {
        logPs = newStack!real(proportions.length);
        size_t pIndex;
        foreach(p; proportions) {
            logPs[pIndex++] = p;
        }
    } else {
        auto app = appender(&logPs);
        foreach(p; proportions) {
            app.put(p);
        }
    }
    logPs[] /= reduce!"a + b"(logPs);
    foreach(ref elem; logPs) {
        elem = log(elem);
    }

    real[] logs = newStack!real(N + 1);
    logs[0] = 0;
    foreach(i; 1..logs.length) {
        logs[i] = log(i);
    }

    real nFact = logFactorial(N);
    real pVal = 0;
    uint nLeft = N;
    real pSoFar = nFact;

    real pActual = nFact;
    foreach(i, count; counts) {
        pActual += logPs[i] * count - logFactorial(count);
    }
    pActual -= pActual * 1e-6;  // Epsilon to handle numerical inaccuracy.

    void doIt(uint pos) {
        if(pos == counts.length - 1) {
            immutable pOld = pSoFar;
            pSoFar += logPs[$ - 1] * nLeft - logFactorial(nLeft);

            if(pSoFar <= pActual) {
                pVal += exp(pSoFar);
            }
            pSoFar = pOld;
            return;
        }

        uint nLeftOld = nLeft;
        immutable pOld = pSoFar;
        real pAdd = 0;

        foreach(i; 0..nLeft + 1) {
            if(i > 0) {
                pAdd += logPs[pos] - logs[i];
            }
            pSoFar = pOld + pAdd;
            doIt(pos + 1);
            nLeft--;
        }
        nLeft = nLeftOld;
        pSoFar = pOld;
    }
    doIt(0);
    return pVal;
}

unittest {
    // Nothing to test this against for more than 1 df, but it matches
    // chi-square roughly and should take the same paths for 2 vs. N degrees
    // of freedom.
    for(uint n = 4; n <= 100; n += 4) {
        foreach(k; 0..n + 1) {
            for(real p = 0.05; p <= 0.95; p += 0.05) {
                real bino = binomialTest(k, n, p);
                real[] ps = [p, 1 - p];
                uint[] counts = [k, n - k];
                real multino = multinomialTest(counts, ps);
                //writeln(k, "\t", n, "\t", p, "\t", bino, "\t", multino);
                assert(approxEqual(bino, multino));
            }
        }
    }
    writeln("Passed multinomialTest test.");
}

/**Performs a Pearson's chi-square test on a contingency table of arbitrary
 * dimensions.  When the chi-square test is mentioned, this is usually the one
 * being referred to.  Takes a set of finite forward ranges, one for each column
 * in the contingency table.  These can be expressed either as a tuple of ranges
 * or a range of ranges.  Returns a P-value for the alternative hypothesis that
 * frequencies in each row of the contingency table depend on the column against
 * the null that they don't.
 *
 * Notes:  The chi-square test relies on asymptotic statistical properties
 * and is therefore not exact.  The typical rule of thumb is that each cell
 * should have an expected value of at least 5.  However, this is likely to
 * be unnecessarily stringent.
 *
 * Yates's continuity correction is never used in this implementation.  If
 * you want something conservative, use fisherExact().
 *
 * This is, for all practical purposes, an inherently non-directional test.
 * Therefore, the one-sided verses two-sided option is not provided.
 *
 * For 2x2 contingency tables, fisherExact is a more conservative test, in that
 * the type I error rate is guaranteed to never be above the nominal P-value.
 * However, even for small sample sizes this test may produce results closer
 * to the true P-value, at the risk of possibly being non-conservative.
 *
 * Examples:
 * ---
 * // Test to see whether the relative frequency of outcome 0, 1, and 2
 * // depends on the treatment in some hypothetical experiment.
 * uint[] drug1 = [1000, 2000, 1500];
 * uint[] drug2 = [1500, 3000, 2300];
 * uint[] placebo = [500, 1100, 750];
 * assert(approxEqual(chiSqrContingency(drug1, drug2, placebo), 0.2397));
 * ---
 */
TestRes chiSqrContingency(T...)(T inputData) {
    return testContingency!(pearsonChiSqElem, T)(inputData);
}

unittest {
    // Test array version.  Using VassarStat's chi-square calculator.
    uint[][] table1 = [[60, 80, 70],
                       [20, 50, 40],
                       [10, 15, 11]];
    uint[][] table2 = [[60, 20, 10],
                       [80, 50, 15],
                       [70, 40, 11]];
    assert(approxEqual(chiSqrContingency(table1), 0.3449));
    assert(approxEqual(chiSqrContingency(table2), 0.3449));
    assert(approxEqual(chiSqrContingency(table1).testStat, 4.48));

    // Test tuple version.
    auto p1 = chiSqrContingency(cast(uint[]) [31, 41, 59],
                                cast(uint[]) [26, 53, 58],
                                cast(uint[]) [97, 93, 93]);
    assert(approxEqual(p1, 0.0059));

    auto p2 = chiSqrContingency(cast(uint[]) [31, 26, 97],
                                cast(uint[]) [41, 53, 93],
                                cast(uint[]) [59, 58, 93]);
    assert(approxEqual(p2, 0.0059));

    uint[] drug1 = [1000, 2000, 1500];
    uint[] drug2 = [1500, 3000, 2300];
    uint[] placebo = [500, 1100, 750];
    assert(approxEqual(chiSqrContingency(drug1, drug2, placebo), 0.2397));

    writeln("Passed chiSqrContingency test.");
}

/**The G or likelihood ratio chi-square test for contingency tables.  Roughly
 * the same as Pearson's chi-square test (chiSqrContingency), but may be more
 * accurate in certain situations and less accurate in others.  However, it
 * is still based on asymptotic distributions, and is not exact. Usage is is
 * identical to chiSqrContingency.
 */
TestRes gTestContingency(T...)(T inputData) {
    return testContingency!(gTestElem, T)(inputData);
}

unittest {
    // Values from example at http://udel.edu/~mcdonald/statgtestind.html
    // Handbook of Biological Statistics.
    uint[] withoutCHD = [268, 199, 42];
    uint[] withCHD = [807, 759, 184];
    auto res = gTestContingency(withoutCHD, withCHD);
    assert(approxEqual(res.testStat, 7.3));
    assert(approxEqual(res.p, 0.026));

    uint[] moringa = [127, 99, 264];
    uint[] vicinus = [116, 67, 161];
    auto res2 = gTestContingency(moringa, vicinus);
    assert(approxEqual(res2.testStat, 6.23));
    assert(approxEqual(res2.p, 0.044));
    writeln("Passed gTestContingency test.");
}

// Pearson and likelihood ratio code are pretty much the same.  Factor out
// the one difference into a function that's a template parameter.  However,
// for API simplicity, this is hidden and they look like two separate functions.
private TestRes testContingency(alias elemFun, T...)(T rangesIn) {
    mixin(newFrame);
    static if(isForwardRange!(T[0]) && T.length == 1 &&
        isForwardRange!(typeof(rangesIn[0].front()))) {
        auto ranges = tempdup(rangesIn[0]);
    } else static if(allSatisfy!(isForwardRange, typeof(rangesIn))) {
        alias rangesIn ranges;
    } else {
        static assert(0, "Can only perform contingency table test" ~
            " on a tuple of ranges or a range of ranges.");
    }

    real[] colSums = newStack!(real)(ranges.length);
    colSums[] = 0;
    size_t nCols = 0;
    size_t nRows = ranges.length;
    foreach(ri, range; ranges) {
        size_t curLen = 0;
        foreach(elem; range) {
            colSums[ri] += cast(real) elem;
            curLen++;
        }
        if(ri == 0) {
            nCols = curLen;
        } else {
            assert(curLen == nCols);
        }
    }

    bool noneEmpty() {
        foreach(range; ranges) {
            if(range.empty) {
                return false;
            }
        }
        return true;
    }

    void popAll() {
        foreach(i, range; ranges) {
            ranges[i].popFront;
        }
    }

    real sumRow() {
        real rowSum = 0;
        foreach(range; ranges) {
            rowSum += cast(real) range.front;
        }
        return rowSum;
    }

    real chiSq = 0;
    real NNeg1 = 1.0L / sum(colSums);
    while(noneEmpty) {
        auto rowSum = sumRow();
        foreach(ri, range; ranges) {
            real expected = NNeg1 * rowSum * colSums[ri];
            chiSq += elemFun(range.front, expected);
        }
        popAll();
    }

    return TestRes(chiSq, chiSqrCDFR(chiSq, (nRows - 1) * (nCols - 1)));
}

private real pearsonChiSqElem(real observed, real expected) {
    real diff = observed - expected;
    return diff * diff / expected;
}

private real gTestElem(real observed, real expected) {
    return observed * log(observed / expected) * 2;
}

/**Fisher's Exact test for difference in odds between rows/columns
 * in a 2x2 contingency table.  Specifically, this function tests the odds
 * ratio, which is defined, for a contingency table c, as (c[0][0] * c[1][1])
 *  / (c[1][0] * c[0][1]).  Alternatives are Alt.LESS, meaning true odds ratio
 * < 1, Alt.GREATER, meaning true odds ratio > 1, and Alt.TWOSIDE, meaning
 * true odds ratio != 1.
 *
 * Accepts a 2x2 contingency table as an array of arrays of uints.
 * For now, only does 2x2 contingency tables.
 *
 * Notes:  Although this test is "exact" in that it does not rely on asymptotic
 * approximations, it is very statistically conservative when the marginals
 * are not truly fixed in the experimental design in question.  If a
 * closer but possibly non-conservative approximation of the true P-value is
 * desired, Pearson's chi-square test (chiSqrContingency) may perform better,
 * even for small samples.
 *
 * Returns:  A TestRes of the odds ratio and the P-value against the given
 * alternative.
 *
 * Examples:
 * ---
 * real res = fisherExact([[2u, 7], [8, 2]], Alt.LESS);
 * assert(approxEqual(res.p, 0.01852));  // Odds ratio is very small in this case.
 * assert(approxEqual(res.testStat, 4.0 / 56.0));
 * ---
 * */
TestRes fisherExact(T)(const T[2][2] contingencyTable, Alt alt = Alt.TWOSIDE)
if(isIntegral!(T)) {

    static real fisherLower(const uint[2][2] contingencyTable) {
        alias contingencyTable c;
        return hypergeometricCDF(c[0][0], c[0][0] + c[0][1], c[1][0] + c[1][1],
                                 c[0][0] + c[1][0]);
    }

    static real fisherUpper(const uint[2][2] contingencyTable) {
        alias contingencyTable c;
        return hypergeometricCDFR(c[0][0], c[0][0] + c[0][1], c[1][0] + c[1][1],
                                 c[0][0] + c[1][0]);
    }


    alias contingencyTable c;
    real oddsRatio = cast(real) c[0][0] * c[1][1] / c[0][1] / c[1][0];
    if(alt == Alt.NONE) {
        return TestRes(oddsRatio);
    } else if(alt == Alt.LESS) {
        return TestRes(oddsRatio, fisherLower(contingencyTable));
    } else if(alt == Alt.GREATER) {
        return TestRes(oddsRatio, fisherUpper(contingencyTable));
    }


    immutable uint n1 = c[0][0] + c[0][1],
                   n2 = c[1][0] + c[1][1],
                   n  = c[0][0] + c[1][0];

    immutable uint mode =
        cast(uint) ((cast(real) (n + 1) * (n1 + 1)) / (n1 + n2 + 2));
    immutable real pExact = hypergeometricPMF(c[0][0], n1, n2, n);
    immutable real pMode = hypergeometricPMF(mode, n1, n2, n);

    if(approxEqual(pExact, pMode, 1e-7)) {
        return TestRes(oddsRatio, 1);
    } else if(c[0][0] < mode) {
        immutable real pLower = hypergeometricCDF(c[0][0], n1, n2, n);

        // Special case to prevent binary search from getting stuck.
        if(hypergeometricPMF(n, n1, n2, n) > pExact) {
            return TestRes(oddsRatio, pLower);
        }

        // Binary search for where to begin upper half.
        uint min = mode, max = n, guess = uint.max;
        while(min != max) {
            guess = (max == min + 1 && guess == min) ? max :
                    (cast(ulong) max + cast(ulong) min) / 2UL;

            immutable real pGuess = hypergeometricPMF(guess, n1, n2, n);
            if(pGuess <= pExact &&
                hypergeometricPMF(guess - 1, n1, n2, n) > pExact) {
                break;
            } else if(pGuess < pExact) {
                max = guess;
            } else min = guess;
        }
        if(guess == uint.max && min == max)
            guess = min;

        auto p = std.algorithm.min(pLower +
               hypergeometricCDFR(guess, n1, n2, n), 1.0L);
        return TestRes(oddsRatio, p);
    } else {
        immutable real pUpper = hypergeometricCDFR(c[0][0], n1, n2, n);

        // Special case to prevent binary search from getting stuck.
        if(hypergeometricPMF(0, n1, n2, n) > pExact) {
            return TestRes(oddsRatio, pUpper);
        }

        // Binary search for where to begin lower half.
        uint min = 0, max = mode, guess = uint.max;
        while(min != max) {
            guess = (max == min + 1 && guess == min) ? max :
                    (cast(ulong) max + cast(ulong) min) / 2UL;
            real pGuess = hypergeometricPMF(guess, n1, n2, n);

            if(pGuess <= pExact &&
                hypergeometricPMF(guess + 1, n1, n2, n) > pExact) {
                break;
            } else if(pGuess <= pExact) {
                min = guess;
            } else max = guess;
        }

        if(guess == uint.max && min == max)
            guess = min;

        auto p = std.algorithm.min(pUpper +
               hypergeometricCDF(guess, n1, n2, n), 1.0L);
        return TestRes(oddsRatio, p);
    }
}

/**Convenience function.  Converts a dynamic array to a static one, then
 * calls the overload.*/
TestRes fisherExact(T)(const T[][] contingencyTable, Alt alt = Alt.TWOSIDE)
if(isIntegral!(T))
in {
    assert(contingencyTable.length == 2);
    assert(contingencyTable[0].length == 2);
    assert(contingencyTable[1].length == 2);
} body {
    uint[2][2] newTable;
    newTable[0][0] = contingencyTable[0][0];
    newTable[0][1] = contingencyTable[0][1];
    newTable[1][1] = contingencyTable[1][1];
    newTable[1][0] = contingencyTable[1][0];
    return fisherExact(newTable, alt);
}

unittest {
    // Simple, naive impl. of two-sided to test against.
    static real naive(const uint[][] c) {
        immutable uint n1 = c[0][0] + c[0][1],
                   n2 = c[1][0] + c[1][1],
                   n  = c[0][0] + c[1][0];
        immutable uint mode =
            cast(uint) ((cast(real) (n + 1) * (n1 + 1)) / (n1 + n2 + 2));
        immutable real pExact = hypergeometricPMF(c[0][0], n1, n2, n);
        immutable real pMode = hypergeometricPMF(mode, n1, n2, n);
        if(approxEqual(pExact, pMode, 1e-7))
            return 1;
        real sum = 0;
        foreach(i; 0..n + 1) {
            real pCur = hypergeometricPMF(i, n1, n2, n);
            if(pCur <= pExact)
                sum += pCur;
        }
        return sum;
    }

    uint[][] c = new uint[][](2, 2);

    foreach(i; 0..1000) {
        c[0][0] = uniform(0U, 51U);
        c[0][1] = uniform(0U, 51U);
        c[1][0] = uniform(0U, 51U);
        c[1][1] = uniform(0U, 51U);
        real naiveAns = naive(c);
        real fastAns = fisherExact(c);
        assert(approxEqual(naiveAns, fastAns));
    }

    auto res = fisherExact([[19000u, 80000], [20000, 90000]]);
    assert(approxEqual(res.testStat, 1.068731));
    assert(approxEqual(res, 3.319e-9));
    res = fisherExact([[18000u, 80000], [20000, 90000]]);
    assert(approxEqual(res, 0.2751));
    res = fisherExact([[14500u, 20000], [30000, 40000]]);
    assert(approxEqual(res, 0.01106));
    res = fisherExact([[100u, 2], [1000, 5]]);
    assert(approxEqual(res, 0.1301));
    res = fisherExact([[2u, 7], [8, 2]]);
    assert(approxEqual(res, 0.0230141));
    res = fisherExact([[5u, 1], [10, 10]]);
    assert(approxEqual(res, 0.1973244));
    res = fisherExact([[5u, 15], [20, 20]]);
    assert(approxEqual(res, 0.0958044));
    res = fisherExact([[5u, 16], [20, 25]]);
    assert(approxEqual(res, 0.1725862));
    res = fisherExact([[10u, 5], [10, 1]]);
    assert(approxEqual(res, 0.1973244));
    res = fisherExact([[2u, 7], [8, 2]], Alt.LESS);
    assert(approxEqual(res, 0.01852));
    res = fisherExact([[5u, 1], [10, 10]], Alt.LESS);
    assert(approxEqual(res, 0.9783));
    res = fisherExact([[5u, 15], [20, 20]], Alt.LESS);
    assert(approxEqual(res, 0.05626));
    res = fisherExact([[5u, 16], [20, 25]], Alt.LESS);
    assert(approxEqual(res, 0.08914));
    res = fisherExact([[2u, 7], [8, 2]], Alt.GREATER);
    assert(approxEqual(res, 0.999));
    res = fisherExact([[5u, 1], [10, 10]], Alt.GREATER);
    assert(approxEqual(res, 0.1652));
    res = fisherExact([[5u, 15], [20, 20]], Alt.GREATER);
    assert(approxEqual(res, 0.985));
    res = fisherExact([[5u, 16], [20, 25]], Alt.GREATER);
    assert(approxEqual(res, 0.9723));
    writeln("Passed fisherExact test.");
}

/**Performs a Kolmogorov-Smirnov (K-S) 2-sample test.  The K-S test is a
 * non-parametric test for a difference between two empirical distributions or
 * between an empirical distribution and a reference distribution.
 *
 * Returns:  A TestRes with the K-S D value and a P value for the null that
 * FPrime is distributed identically to F against the alternative that it isn't.
 * This implementation uses a signed D value to indicate the direction of the
 * difference between distributions.  To get the D value used in standard
 * notation, simply take the absolute value of this D value.
 *
 * Bugs:  Exact calculation not implemented.  Uses asymptotic approximation.*/
TestRes ksTest(T, U)(T F, U Fprime)
if(realInput!(T) && realInput!(U)) {
    real D = ksTestD(F, Fprime);
    return TestRes(D, ksPval(F.length, Fprime.length, D));
}

unittest {
    assert(approxEqual(ksTest([1,2,3,4,5].dup, [1,2,3,4,5].dup).testStat, 0));
    assert(approxEqual(ksTestDestructive([1,2,3,4,5].dup, [1,2,2,3,5].dup).testStat, -.2));
    assert(approxEqual(ksTest([-1,0,2,8, 6].dup, [1,2,2,3,5].dup).testStat, .4));
    assert(approxEqual(ksTest([1,2,3,4,5].dup, [1,2,2,3,5,7,8].dup).testStat, .2857));
    assert(approxEqual(ksTestDestructive([1, 2, 3, 4, 4, 4, 5].dup,
           [1, 2, 3, 4, 5, 5, 5].dup).testStat, .2857));

    assert(approxEqual(ksTest([1, 2, 3, 4, 4, 4, 5].dup, [1, 2, 3, 4, 5, 5, 5].dup),
           .9375));
    assert(approxEqual(ksTestDestructive([1, 2, 3, 4, 4, 4, 5].dup,
        [1, 2, 3, 4, 5, 5, 5].dup), .9375));
    writeln("Passed ksTest 2-sample test.");
}

template isArrayLike(T) {
    enum bool isArrayLike = hasSwappableElements!(T) && hasAssignableElements!(T)
        && dstats.base.hasLength!(T) && isRandomAccessRange!(T);
}

/**One-sample KS test against a reference distribution, doesn't modify input
 * data.  Takes a function pointer or delegate for the CDF of refernce
 * distribution.
 *
 * Returns:  A TestRes with the K-S D value and a P value for the null that
 * Femp is a sample from F against the alternative that it isn't. This
 * implementation uses a signed D value to indicate the direction of the
 * difference between distributions.  To get the D value used in standard
 * notation, simply take the absolute value of this D value.
 *
 * Bugs:  Exact calculation not implemented.  Uses asymptotic approximation.
 *
 * Examples:
 * ---
 * auto stdNormal = parametrize!(normalCDF)(0.0L, 1.0L);
 * auto empirical = [1, 2, 3, 4, 5];
 * real res = ksTest(empirical, stdNormal);
 * ---
 */
TestRes ksTest(T, Func)(T Femp, Func F)
if(realInput!(T) && is(ReturnType!(Func) : real)) {
    real D = ksTestD(Femp, F);
    return TestRes(D, ksPval(Femp.length, D));
}

unittest {
    auto stdNormal = paramFunctor!(normalCDF)(0.0L, 1.0L);
    assert(approxEqual(ksTest([1,2,3,4,5].dup, stdNormal).testStat, -.8413));
    assert(approxEqual(ksTestDestructive([-1,0,2,8, 6].dup, stdNormal).testStat, -.5772));
    auto lotsOfTies = [5,1,2,2,2,2,2,2,3,4].dup;
    assert(approxEqual(ksTest(lotsOfTies, stdNormal).testStat, -0.8772));

    assert(approxEqual(ksTest([0,1,2,3,4].dup, stdNormal), .03271));

    auto uniform01 = parametrize!(uniformCDF)(0, 1);
    assert(approxEqual(ksTestDestructive([0.1, 0.3, 0.5, 0.9, 1].dup, uniform01), 0.7591));

    writeln("Passed ksTest 1-sample test.");
}

/**Same as ksTest, except sorts in place, avoiding memory allocations.*/
TestRes ksTestDestructive(T, U)(T F, U Fprime)
if(isArrayLike!(T) && isArrayLike!(U)) {
    real D = ksTestDDestructive(F, Fprime);
    return TestRes(D, ksPval(F.length, Fprime.length, D));
}

///Ditto.
TestRes ksTestDestructive(T, Func)(T Femp, Func F)
if(isArrayLike!(T) && is(ReturnType!Func : real)) {
    real D =  ksTestDDestructive(Femp, F);
    return TestRes(D, ksPval(Femp.length, D));
}

real ksTestD(T, U)(T F, U Fprime)
if(isInputRange!(T) && isInputRange!(U)) {
    auto TAState = TempAlloc.getState;
    scope(exit) {
        TempAlloc.free(TAState);
        TempAlloc.free(TAState);
    }
    return ksTestDDestructive(tempdup(F), tempdup(Fprime));
}

real ksTestDDestructive(T, U)(T F, U Fprime)
if(isArrayLike!(T) && isArrayLike!(U)) {
    qsort(F);
    qsort(Fprime);
    real D = 0;
    size_t FprimePos = 0;
    foreach(i; 0..2) {  //Test both w/ Fprime x vals, F x vals.
        real diffMult = (i == 0) ? 1 : -1;
        foreach(FPos, Xi; F) {
            if(FPos < F.length - 1 && F[FPos + 1] == Xi)
                continue;  //Handle ties.
            while(FprimePos < Fprime.length && Fprime[FprimePos] <= Xi) {
                FprimePos++;
            }
            real diff = diffMult * (cast(real) (FPos + 1) / F.length -
                       cast(real) FprimePos / Fprime.length);
            if(abs(diff) > abs(D))
                D = diff;
        }
        swap(F, Fprime);
        FprimePos = 0;
    }
    return D;
}

real ksTestD(T, Func)(T Femp, Func F)
if(realInput!(T) && is(ReturnType!Func : real)) {
    scope(exit) TempAlloc.free;
    return ksTestDDestructive(tempdup(Femp), F);
}

real ksTestDDestructive(T, Func)(T Femp, Func F)
if(isArrayLike!(T) && is(ReturnType!Func : real)) {
    qsort(Femp);
    real D = 0;

    foreach(FPos, Xi; Femp) {
        real diff = cast(real) FPos / Femp.length - F(Xi);
        if(abs(diff) > abs(D))
            D = diff;
    }

    return D;
}

real ksPval(ulong N, ulong Nprime, real D)
in {
    assert(D >= -1);
    assert(D <= 1);
} body {
    return 1 - kolmDist(sqrt(cast(real) (N * Nprime) / (N + Nprime)) * abs(D));
}

real ksPval(ulong N, real D)
in {
    assert(D >= -1);
    assert(D <= 1);
} body {
    return 1 - kolmDist(abs(D) * sqrt(cast(real) N));
}

/**Wald-wolfowitz or runs test for randomness of the distribution of
 * elements for which positive() evaluates to true.  For example, given
 * a sequence of coin flips [H,H,H,H,H,T,T,T,T,T] and a positive() function of
 * "a == 'H'", this test would determine that the heads are non-randomly
 * distributed, since they are all at the beginning of obs.  This is done
 * by counting the number of runs of consecutive elements for which
 * positive() evaluates to true, and the number of consecutive runs for which
 * it evaluates to false.  In the example above, we have 2 runs.  These are the
 * block of 5 consecutive heads at the beginning and the 5 consecutive tails
 * at the end.
 *
 * Alternatives are Alt.LESS, meaning that less runs than expected have been
 * observed and data for which positive() is true tends to cluster,
 * Alt.GREATER, which means that more runs than expected have been observed
 * and data for which positive() is true tends to not cluster even moreso than
 * expected by chance, and Alt.TWOSIDE, meaning that elements for which
 * positive() is true cluster as much as expected by chance.
 *
 * Bugs:  No exact calculation of the P-value.  Asymptotic approximation only.
 */
real runsTest(alias positive = "a > 0", T)(T obs, Alt alt = Alt.TWOSIDE)
if(isIterable!(T)) {
    OnlineRunsTest!(positive, IterType!(T)) r;
    foreach(elem; obs) {
        r.put(elem);
    }
    return r.pVal(alt);
}

unittest {
    // Values from R lawstat package, for which "a < median(data)" is
    // hard-coded as the equivalent to positive().  The median of this data
    // is 0.5, so everything works.
    immutable int[] data = [1,0,0,0,1,1,0,0,1,0,1,0,1,0,1,1,1,0,0,1].idup;
    assert(approxEqual(runsTest(data), 0.3581));
    assert(approxEqual(runsTest(data, Alt.LESS), 0.821));
    assert(approxEqual(runsTest(data, Alt.GREATER), 0.1791));
    writeln("Passed runsTest test.");
}

/**Runs test as in runsTest(), except calculates online instead of from stored
 * array elements.*/
struct OnlineRunsTest(alias positive = "a > 0", T) {
private:
    uint nPos;
    uint nNeg;
    uint nRun;
    bool lastPos;

    alias unaryFun!(positive) pos;

public:

    ///
    void put(T elem) {
        bool curPos = pos(elem);
        if(nRun == 0) {
            nRun = 1;
            if(curPos) {
                nPos++;
            } else {
                nNeg++;
            }
        } else if(pos(elem)) {
            nPos++;
            if(!lastPos) {
                nRun++;
            }
        } else {
            nNeg++;
            if(lastPos) {
                nRun++;
            }
        }
        lastPos = curPos;
    }

    ///
    uint nRuns() {
        return nRun;
    }

    ///
    real pVal(Alt alt = Alt.TWOSIDE) {
        uint N = nPos + nNeg;
        real expected = 2.0L * nPos * nNeg / N + 1;
        real sd = sqrt((expected - 1) * (expected - 2) / (N - 1));
        if(alt == Alt.LESS) {
            return normalCDF(nRun, expected, sd);
        } else if(alt == Alt.GREATER) {
            return normalCDFR(nRun, expected, sd);
        } else {
            return 2 * min(normalCDF(nRun, expected, sd),
                           normalCDFR(nRun, expected, sd));
        }
    }
}

/**Tests the hypothesis that the Pearson correlation between two ranges is
 * different from some 0.  Alternatives are
 * Alt.LESS (pcor(range1, range2) < 0), Alt.GREATER (pcor(range1, range2)
 * > 0) and Alt.TWOSIDE (pcor(range1, range2) != 0).
 *
 * Returns:  A ConfInt of the estimated Pearson correlation of the two ranges,
 * the P-value against the given alternative, and the confidence interval of
 * the correlation at the level specified by confLevel.*/
ConfInt pcorTest(T, U)(T range1, U range2, Alt alt = Alt.TWOSIDE, real confLevel = 0.95)
if(realInput!(T) && realInput!(U)) {
    OnlinePcor res;
    while(!range1.empty && !range2.empty) {
        res.put(range1.front, range2.front);
        range1.popFront;
        range2.popFront;
    }
    return finishPearsonSpearman(res.cor, res.N, alt, confLevel);
}

unittest {
    // Values from R.
    auto t1 = pcorTest([1,2,3,4,5].dup, [2,1,4,3,5].dup, Alt.TWOSIDE);
    auto t2 = pcorTest([1,2,3,4,5].dup, [2,1,4,3,5].dup, Alt.LESS);
    auto t3 = pcorTest([1,2,3,4,5].dup, [2,1,4,3,5].dup, Alt.GREATER);

    assert(approxEqual(t1.testStat, 0.8));
    assert(approxEqual(t2.testStat, 0.8));
    assert(approxEqual(t3.testStat, 0.8));

    assert(approxEqual(t1.p, 0.1041));
    assert(approxEqual(t2.p, 0.948));
    assert(approxEqual(t3.p, 0.05204));

    assert(approxEqual(t1.lowerBound, -0.2796400));
    assert(approxEqual(t3.lowerBound, -0.06438567));
    assert(approxEqual(t2.lowerBound, -1));

    assert(approxEqual(t1.upperBound, 0.9861962));
    assert(approxEqual(t2.upperBound, 0.9785289));
    assert(approxEqual(t3.upperBound, 1));

    writeln("Passed pcorSig test.");
}

/**Tests the hypothesis that the Spearman correlation between two ranges is
 * different from some 0.  Alternatives are
 * Alt.LESS (scor(range1, range2) < 0), Alt.GREATER (scor(range1, range2)
 * > 0) and Alt.TWOSIDE (scor(range1, range2) != 0).
 *
 * Returns:  A TestRes containing the Spearman correlation coefficient and
 * the P-value for the given alternative.
 *
 * Bugs:  Exact P-value computation not yet implemented.  Uses asymptotic
 * approximation only.  This is good enough for most practical purposes given
 * reasonably large N, but is not perfectly accurate.  Not valid for data with
 * very large amounts of ties.  */
TestRes scorTest(T, U)(T range1, U range2, Alt alt = Alt.TWOSIDE)
if(isInputRange!(T) && isInputRange!(U) &&
   dstats.base.hasLength!(T) && dstats.base.hasLength!(U)) {
    real N = range1.length;
    return finishPearsonSpearman(scor(range1, range2), N, alt, 0);
}

unittest {
    // Values from R.
    int[] arr1 = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
    int[] arr2 = [8,6,7,5,3,0,9,8,6,7,5,3,0,9,3,6,2,4,3,6,8];
    auto t1 = scorTest(arr1, arr2, Alt.TWOSIDE);
    auto t2 = scorTest(arr1, arr2, Alt.LESS);
    auto t3 = scorTest(arr1, arr2, Alt.GREATER);

    assert(approxEqual(t1.testStat, -0.1769406));
    assert(approxEqual(t2.testStat, -0.1769406));
    assert(approxEqual(t3.testStat, -0.1769406));

    assert(approxEqual(t1.p, 0.4429));
    assert(approxEqual(t3.p, 0.7785));
    assert(approxEqual(t2.p, 0.2215));

    writeln("Passed scorSig test.");
}

private ConfInt finishPearsonSpearman(real cor, real N, Alt alt, real confLevel) {
    real denom = sqrt((1 - cor * cor) / (N - 2));
    real t = cor / denom;
    ConfInt ret;
    ret.testStat = cor;
    real sqN = sqrt(N - 3);
    real z = sqN * atanh(cor);
    switch(alt) {
        case Alt.NONE :
            return ret;
        case Alt.TWOSIDE:
            ret.p = 2 * min(studentsTCDF(t, N - 2), studentsTCDFR(t, N - 2));
            real deltaZ = invNormalCDF(0.5 * (1 - confLevel));
            ret.lowerBound = tanh((z + deltaZ) / sqN);
            ret.upperBound = tanh((z - deltaZ) / sqN);
            break;
        case Alt.LESS:
            ret.p = studentsTCDF(t, N - 2);
            real deltaZ = invNormalCDF(1 - confLevel);
            ret.lowerBound = -1;
            ret.upperBound = tanh((z - deltaZ) / sqN);
            break;
        case Alt.GREATER:
            ret.p = studentsTCDFR(t, N - 2);
            real deltaZ = invNormalCDF(1 - confLevel);
            ret.lowerBound = tanh((z + deltaZ) / sqN);
            ret.upperBound = 1;
            break;
        default:
            assert(0);
    }
    return ret;
}

/**Tests the hypothesis that the Kendall correlation between two ranges is
 * different from some 0.  Alternatives are
 * Alt.LESS (kcor(range1, range2) < 0), Alt.GREATER (kcor(range1, range2)
 * > 0) and Alt.TWOSIDE (kcor(range1, range2) != 0).
 *
 * exactThresh controls the maximum length of the range for which exact P-value
 * computation is used.  The default is 50.  Exact calculation is never used
 * when ties are present because it is not computationally feasible.
 * Do not set this higher than 100, as it will be very slow
 * and the asymptotic approximation is pretty good at even a fraction of this
 * size.
 *
 * Returns:  A TestRes containing the Kendall correlation coefficient and
 * the P-value for the given alternative.
 */
TestRes kcorTest(T, U)(T range1, U range2, Alt alt = Alt.TWOSIDE, uint exactThresh = 50)
if(isInputRange!(T) && isInputRange!(U)) {
    mixin(newFrame);
    auto i1d = tempdup(range1);
    auto i2d = tempdup(range2);
    auto res = kcorDestructiveLowLevel(i1d, i2d);

    real n = i1d.length;
    real sd = sqrt((n * (n - 1) * (2 * n + 5) - res.field[2]) / 18.0L);
    enum real cc = 1;
    auto tau = res.field[0];
    auto s = res.field[1];

    if(res.field[2] == 0 && n <= exactThresh) {
        uint N = i1d.length;
        uint nSwaps = (N * (N - 1) / 2 - s) / 2;
        return TestRes(tau, kcorExactP(N, nSwaps, alt));
    }

    switch(alt) {
        case Alt.NONE :
            return TestRes(tau);
        case Alt.TWOSIDE:
            return TestRes(tau, 2 * min(normalCDF(s + cc, 0, sd),
                           normalCDFR(s - cc, 0, sd), 0.5));
        case Alt.LESS:
            return TestRes(tau, normalCDF(s + cc, 0, sd));
        case Alt.GREATER:
            return TestRes(tau, normalCDFR(s - cc, 0, sd));
        default:
            assert(0);
    }
}

// Dynamic programming algorithm for computing exact Kendall tau P-values.
// Thanks to ShreevatsaR from StackOverflow.
real kcorExactP(uint N, uint swaps, Alt alt) {
    uint maxSwaps = N * (N - 1) / 2;
    assert(swaps <= maxSwaps);
    real expectedSwaps = N * (N - 1) * 0.25L;
    if(alt == Alt.GREATER) {
        if(swaps > expectedSwaps) {
            if(swaps == maxSwaps) {
                return 1;
            }
            return 1.0L - kcorExactP(N, maxSwaps - swaps - 1, Alt.GREATER);
        }
    } else if(alt == Alt.LESS) {
        if(swaps == 0) {
            return 1;
        }
        return kcorExactP(N, maxSwaps - swaps + 0, Alt.GREATER);
    } else if(alt == Alt.TWOSIDE) {
        if(swaps < expectedSwaps) {
            return min(1, 2 * kcorExactP(N, swaps, Alt.GREATER));
        } else if(swaps > expectedSwaps) {
            return min(1, 2 * kcorExactP(N, swaps, Alt.LESS));
        } else {
            return 1;
        }
    } else {  // Alt.NONE
        return real.nan;
    }

    real pElem = exp(-logFactorial(N));
    real[] cur = newStack!real(swaps + 1);
    real[] prev = newStack!real(swaps + 1);

    prev[] = pElem;
    cur[0] = pElem;
    foreach(i; 1..N + 1) {
        uint nSwapsPossible = i * (i - 1) / 2;
        uint upTo = min(swaps, nSwapsPossible) + 1;
        foreach(j; 1..upTo) {
            if(j < i) {
                cur[j] = prev[j] + cur[j - 1];
            } else {
                cur[j] = prev[j] - prev[j - i] + cur[j - 1];
            }
        }
        cur[upTo..$] = cur[upTo - 1];
        swap(cur, prev);
    }
    TempAlloc.free;
    TempAlloc.free;
    return prev[$ - 1];
}

unittest {
    // Values from R.  The epsilon for P-vals will be relatively large because
    // R's approximate function does not use a continuity correction, and is
    // therefore quite bad.

    int[] arr1 = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
    int[] arr2 = [8,6,7,5,3,0,9,8,6,7,5,3,0,9,3,6,2,4,3,6,8];
    auto t1 = kcorTest(arr1, arr2, Alt.TWOSIDE);
    auto t2 = kcorTest(arr1, arr2, Alt.LESS);
    auto t3 = kcorTest(arr1, arr2, Alt.GREATER);

    assert(approxEqual(t1.testStat, -.1448010));
    assert(approxEqual(t2.testStat, -.1448010));
    assert(approxEqual(t3.testStat, -.1448010));

    assert(approxEqual(t1.p, 0.3757, 0.0, 0.02));
    assert(approxEqual(t3.p, 0.8122, 0.0, 0.02));
    assert(approxEqual(t2.p, 0.1878, 0.0, 0.02));

    // Test the exact stuff.  Still using values from R.
    uint[] foo = [1,2,3,4,5];
    uint[] bar = [1,2,3,5,4];
    uint[] baz = [5,3,1,2,4];

    assert(approxEqual(kcorTest(foo, foo).p, 0.01666666));
    assert(approxEqual(kcorTest(foo, foo, Alt.GREATER).p, 0.008333333));
    assert(approxEqual(kcorTest(foo, foo, Alt.LESS).p, 1));

    assert(approxEqual(kcorTest(foo, bar).p, 0.083333333));
    assert(approxEqual(kcorTest(foo, bar, Alt.GREATER).p, 0.041666667));
    assert(approxEqual(kcorTest(foo, bar, Alt.LESS).p, 0.9917));

    assert(approxEqual(kcorTest(foo, baz).p, 0.8167));
    assert(approxEqual(kcorTest(foo, baz, Alt.GREATER).p, 0.7583));
    assert(approxEqual(kcorTest(foo, baz, Alt.LESS).p, .4083));

    assert(approxEqual(kcorTest(bar, baz).p, 0.4833));
    assert(approxEqual(kcorTest(bar, baz, Alt.GREATER).p, 0.8833));
    assert(approxEqual(kcorTest(bar, baz, Alt.LESS).p, 0.2417));

    // A little monte carlo unittesting.  For large ranges, the deviation
    // between the exact and approximate version should be extremely small.
    foreach(i; 0..100) {
        uint nToTake = uniform(15, 35);
        auto lhs = toArray(take(nToTake, randRange!rNorm(0, 1)));
        auto rhs = toArray(take(nToTake, randRange!rNorm(0, 1)));
        if(i & 1) {
            lhs[] += rhs[] * 0.2;  // Make sure there's some correlation.
        } else {
            lhs[] -= rhs[] * 0.2;
        }
        real exact = kcorTest(lhs, rhs).p;
        real approx = kcorTest(lhs, rhs, Alt.TWOSIDE, 0).p;
        assert(abs(exact - approx) < 0.01);

        exact = kcorTest(lhs, rhs, Alt.GREATER).p;
        approx = kcorTest(lhs, rhs, Alt.GREATER, 0).p;
        assert(abs(exact - approx) < 0.01);

        exact = kcorTest(lhs, rhs, Alt.LESS).p;
        approx = kcorTest(lhs, rhs, Alt.LESS, 0).p;
        assert(abs(exact - approx) < 0.01);
    }
    writeln("Passed kcorTest test.");
}

/**A test for normality of the distribution of a range of values.  Based on
 * the assumption that normally distributed values will have a sample skewness
 * and sample kurtosis very close to zero.
 *
 * Returns:  A TestRes with the K statistic, which is Chi-Square distributed
 * with 2 degrees of freedom under the null, and the P-value for the alternative
 * that the data has skewness and kurtosis not equal to zero against the null
 * that skewness and kurtosis are near zero.  A normal distribution always has
 * skewness and kurtosis that converge to zero as sample size goes to infinity.
 *
 * Notes:  Contrary to popular belief, tests for normality should usually
 * not be used to deterimine whether T-tests are valid.  If the sample size is
 * large, T-tests are valid regardless of the distribution due to the central
 * limit theorem.  If the sample size is small, a test for normality will
 * likely not be very powerful, and a priori knowledge or simple inspection
 * of the data is often a better idea.
 *
 * References:
 * D'Agostino, Ralph B., Albert Belanger, and Ralph B. D'Agostino, Jr.
 * "A Suggestion for Using Powerful and Informative Tests of Normality",
 * The American Statistician, Vol. 44, No. 4. (Nov., 1990), pp. 316-321.
 */
TestRes dAgostinoK(T)(T range)
if(realIterable!(T)) {
    // You are not meant to understand this.  I sure don't.  I just implemented
    // these formulas off of Wikipedia, which got them from:

    // D'Agostino, Ralph B., Albert Belanger, and Ralph B. D'Agostino, Jr.
    // "A Suggestion for Using Powerful and Informative Tests of Normality",
    // The American Statistician, Vol. 44, No. 4. (Nov., 1990), pp. 316-321.

    // Amazing.  I didn't even realize things this complicated were possible
    // in 1990, before widespread computer algebra systems.

    // Notation from Wikipedia.  Keeping same notation for simplicity.
    real sqrtb1 = void, b2 = void, n = void;
    {
        auto summ = summary(range);
        sqrtb1 = summ.skew;
        b2 = summ.kurtosis + 3;
        n = summ.N;
    }

    // Calculate transformed skewness.
    real Y = sqrtb1 * sqrt((n + 1) * (n + 3) / (6 * (n - 2)));
    real beta2b1Numer = 3 * (n * n + 27 * n - 70) * (n + 1) * (n + 3);
    real beta2b1Denom = (n - 2) * (n + 5) * (n + 7) * (n + 9);
    real beta2b1 = beta2b1Numer / beta2b1Denom;
    real Wsq = -1 + sqrt(2 * (beta2b1 - 1));
    real delta = 1.0L / sqrt(log(sqrt(Wsq)));
    real alpha = sqrt( 2.0L / (Wsq - 1));
    real Zb1 = delta * log(Y / alpha + sqrt(pow(Y / alpha, 2) + 1));

    // Calculate transformed kurtosis.
    real Eb2 = 3 * (n - 1) / (n + 1);
    real sigma2b2 = (24 * n * (n - 2) * (n - 3)) / (
        (n + 1) * (n + 1) * (n + 3) * (n + 5));
    real x = (b2 - Eb2) / sqrt(sigma2b2);

    real sqBeta1b2 = 6 * (n * n - 5 * n + 2) / ((n + 7) * (n + 9)) *
         sqrt((6 * (n + 3) * (n + 5)) / (n * (n - 2) * (n - 3)));
    real A = 6 + 8 / sqBeta1b2 * (2 / sqBeta1b2 + sqrt(1 + 4 / (sqBeta1b2 * sqBeta1b2)));
    real Zb2 = ((1 - 2 / (9 * A)) -
        cbrt((1 - 2 / A) / (1 + x * sqrt(2 / (A - 4)))) ) *
        sqrt(9 * A / 2);

    real K2 = Zb1 * Zb1 + Zb2 * Zb2;
    return TestRes(K2, chiSqrCDFR(K2, 2));
}

unittest {
    // Values from R's fBasics package.
    int[] arr1 = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
    int[] arr2 = [8,6,7,5,3,0,9,8,6,7,5,3,0,9,3,6,2,4,3,6,8];

    auto r1 = dAgostinoK(arr1);
    auto r2 = dAgostinoK(arr2);

    assert(approxEqual(r1.testStat, 3.1368));
    assert(approxEqual(r1.p, 0.2084));
    writeln("Passed dAgostinoK test.");
}

/**Fisher's method of meta-analyzing a set of P-values to determine whether
 * there are more significant results than would be expected by chance.
 * Based on a chi-square statistic for the sum of the logs of the P-values.
 *
 * Returns:  A TestRes containing the chi-square statistic and a P-value for
 * the alternative hypothesis that more small P-values than would be expected
 * by chance are present against the alternative that the distribution of
 * P-values is uniform or enriched for large P-values.
 *
 * References:  Fisher, R. A. (1948) "Combining independent tests of
 * significance", American Statistician, vol. 2, issue 5, page 30.
 * (In response to Question 14)
 */
TestRes fishersMethod(R)(R pVals)
if(realInput!R) {
    real chiSq = 0;
    uint df = 0;
    foreach(pVal; pVals) {
        chiSq += log( cast(real) pVal);
        df += 2;
    }
    chiSq *= -2;
    return TestRes(chiSq, chiSqrCDFR(chiSq, df));
}

unittest {
    // First, basic sanity check.  Make sure w/ one P-value, we get back that
    // P-value.
    for(real p = 0.01; p < 1; p += 0.01) {
        assert(approxEqual(fishersMethod([p].dup).p, p));
    }
    float[] ps = [0.739, 0.0717, 0.01932, 0.03809];
    auto res = fishersMethod(ps);
    assert(approxEqual(res.testStat, 20.31));
    assert(res.p < 0.01);
    writeln("Passed fishersMethod test.");
}

/// For falseDiscoveryRate.
enum Dependency {
    /// Assume that dependency among hypotheses may exist.  (More conservative.)
    TRUE,

    /// Assume hypotheses are independent.  (Less conservative.)
    FALSE
}

/**Computes the false discovery rate statistic given a list of
 * p-values, according to Benjamini and Hochberg (1995) (independent) or
 * Benjamini and Yekutieli (2001) (dependent).  The Dependency parameter
 * controls whether hypotheses are assumed to be independent, or whether
 * the more conservative assumption that they are correlated must be made.
 *
 * Returns:
 * An array of adjusted P-values with indices corresponding to the order of
 * the P-values in the input data.
 *
 * References:
 * Benjamini, Y., and Hochberg, Y. (1995). Controlling the false discovery rate:
 * a practical and powerful approach to multiple testing. Journal of the Royal
 * Statistical Society Series B, 57, 289-200
 *
 * Benjamini, Y., and Yekutieli, D. (2001). The control of the false discovery
 * rate in multiple testing under dependency. Annals of Statistics 29, 1165-1188.
 */
float[] falseDiscoveryRate(T)(T pVals, Dependency dep = Dependency.FALSE)
if(realInput!(T)) {
    float[] qVals;
    auto app = appender(&qVals);
    app.put(pVals);

    real C = 1;
    if(dep == Dependency.TRUE) {
        foreach(i; 2..qVals.length + 1) {
            C += 1.0L / i;
        }
    }

    mixin(newFrame);
    auto perm = newStack!(uint)(qVals.length);
    foreach(i, ref elem; perm)
        elem = i;

    qsort(qVals, perm);

    foreach(i, ref q; qVals) {
        q = min(1.0f, q * C * cast(real) qVals.length / (cast(real) i + 1));
    }

    float smallestSeen = float.max;
    foreach_reverse(ref q; qVals) {
        if(q < smallestSeen) {
            smallestSeen = q;
        } else {
            q = smallestSeen;
        }
    }

    qsort(perm, qVals);  //Makes order of qVals correspond to input.
    return qVals;
}

unittest {
    // Comparing results to R.
    auto pVals = [.90, .01, .03, .03, .70, .60, .01].dup;
    auto qVals = falseDiscoveryRate(pVals);
    alias approxEqual ae;
    assert(ae(qVals[0], .9));
    assert(ae(qVals[1], .035));
    assert(ae(qVals[2], .052));
    assert(ae(qVals[3], .052));
    assert(ae(qVals[4], .816666666667));
    assert(ae(qVals[5], .816666666667));
    assert(ae(qVals[6], .035));

    auto p2 = [.1, .02, .6, .43, .001].dup;
    auto q2 = falseDiscoveryRate(p2);
    assert(ae(q2[0], .16666666));
    assert(ae(q2[1], .05));
    assert(ae(q2[2], .6));
    assert(ae(q2[3], .5375));
    assert(ae(q2[4], .005));

    // Dependent case.
    qVals = falseDiscoveryRate(pVals, Dependency.TRUE);
    assert(ae(qVals[0], 1));
    assert(ae(qVals[1], .09075));
    assert(ae(qVals[2], .136125));
    assert(ae(qVals[3], .136125));
    assert(ae(qVals[4], 1));
    assert(ae(qVals[5], 1));
    assert(ae(qVals[6], .09075));

    q2 = falseDiscoveryRate(p2, Dependency.TRUE);
    assert(ae(q2[0], .38055555));
    assert(ae(q2[1], .1141667));
    assert(ae(q2[2], 1));
    assert(ae(q2[3], 1));
    assert(ae(q2[4], .01141667));

    writeln("Passed falseDiscoveryRate test.");
}

/**Uses the Hochberg procedure to control the familywise error rate assuming
 * that hypothesis tests are independent.  This is more powerful than
 * Holm-Bonferroni correction, but requires the independence assumption.
 *
 * Returns:
 * An array of adjusted P-values with indices corresponding to the order of
 * the P-values in the input data.
 *
 * References:
 * Hochberg, Y. (1988). A sharper Bonferroni procedure for multiple tests of
 * significance. Biometrika, 75, 800-803.
 */
float[] hochberg(T)(T pVals)
if(realInput!(T)) {
    float[] qVals;
    auto app = appender(&qVals);
    app.put(pVals);

    mixin(newFrame);
    auto perm = newStack!(uint)(qVals.length);
    foreach(i, ref elem; perm)
        elem = i;

    qsort(qVals, perm);

    foreach(i, ref q; qVals) {
        q = min(1.0f, q * (cast(real) qVals.length - i));
    }

    float smallestSeen = float.max;
    foreach_reverse(ref q; qVals) {
        if(q < smallestSeen) {
            smallestSeen = q;
        } else {
            q = smallestSeen;
        }
    }

    qsort(perm, qVals);  //Makes order of qVals correspond to input.
    return qVals;
}

unittest {
    alias approxEqual ae;
    auto q = hochberg([0.01, 0.02, 0.025, 0.9].dup);
    assert(ae(q[0], 0.04));
    assert(ae(q[1], 0.05));
    assert(ae(q[2], 0.05));
    assert(ae(q[3], 0.9));

    auto p2 = [.1, .02, .6, .43, .001].dup;
    auto q2 = hochberg(p2);
    assert(ae(q2[0], .3));
    assert(ae(q2[1], .08));
    assert(ae(q2[2], .6));
    assert(ae(q2[3], .6));
    assert(ae(q2[4], .005));
    writeln("Passed Hochberg unittest.");
}

/**Uses the Holm-Bonferroni method to adjust a set of P-values in a way that
 * controls the familywise error rate (The probability of making at least one
 * Type I error).  This is basically a less conservative version of
 * Bonferroni correction that is still valid for arbitrary assumptions and
 * controls the familywise error rate.  Therefore, there aren't too many good
 * reasons to use regular Bonferroni correction instead.
 *
 * Returns:
 * An array of adjusted P-values with indices corresponding to the order of
 * the P-values in the input data.
 *
 * References:
 * Holm, S. (1979). A simple sequentially rejective multiple test procedure.
 * Scandinavian Journal of Statistics, 6, 65-70.
 */
float[] holmBonferroni(T)(T pVals)
if(realInput!(T)) {
    mixin(newFrame);

    float[] qVals;
    auto app = appender(&qVals);
    app.put(pVals);

    auto perm = newStack!(uint)(qVals.length);

    foreach(i, ref elem; perm)
        elem = i;
    qsort(qVals, perm);

    foreach(i, ref q; qVals) {
        q = min(1.0L, q * (cast(real) qVals.length - i));
    }

    foreach(i; 1..qVals.length) {
        if(qVals[i] < qVals[i - 1]) {
            qVals[i] = qVals[i - 1];
        }
    }

    qsort(perm, qVals);  //Makes order of qVals correspond to input.
    return qVals;
}

unittest {
    // Values from R.
    auto ps = holmBonferroni([0.001, 0.2, 0.3, 0.4, 0.7].dup);
    alias approxEqual ae;
    assert(ae(ps[0], 0.005));
    assert(ae(ps[1], 0.8));
    assert(ae(ps[2], 0.9));
    assert(ae(ps[3], 0.9));
    assert(ae(ps[4], 0.9));

    ps = holmBonferroni([0.3, 0.1, 0.4, 0.1, 0.5, 0.9].dup);
    assert(ps == [1f, 0.6f, 1f, 0.6f, 1f, 1f]);
    writeln("Passed Holm-Bonferroni unittest.");
}


// Verify that there are no TempAlloc memory leaks anywhere in the code covered
// by the unittest.  This should always be the last unittest of the module.
unittest {
    auto TAState = TempAlloc.getState;
    assert(TAState.used == 0);
    assert(TAState.nblocks < 2);
}
