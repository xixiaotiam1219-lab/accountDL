
/**
 * 模拟图标匹配逻辑验证 (纯 JavaScript 版本)
 */

function cleanName(name) {
    let last;
    let current = name.replace(/^(订阅了|关注了|购买了|开通了)/g, '').trim();
    const noiseRegex = /(超级|至尊|黄金|白金|星钻|大会员|旗舰版|标准版|专业版|会员|VIP|会员卡|订阅|套餐|券|代金券|服务|卡|Premium|Member|PLUS)$/i;
    do {
        last = current;
        current = current.replace(noiseRegex, '').trim();
    } while (current !== last);
    return current;
}

function checkMatch(input, matchedApp) {
    const lowerInput = input.toLowerCase();
    const lowerMatched = matchedApp.toLowerCase();
    return lowerInput.includes(lowerMatched) || lowerMatched.includes(lowerInput);
}

// 测试用例
const testCases = [
    { name: '腾讯视频会员', expectedClean: '腾讯视频', matchWith: '腾讯视频', shouldMatch: true },
    { name: '订阅了爱奇艺', expectedClean: '爱奇艺', matchWith: '爱奇艺', shouldMatch: true },
    { name: '开通了哔哩哔哩大会员', expectedClean: '哔哩哔哩', matchWith: '哔哩哔哩', shouldMatch: true },
    { name: '京东PLUS', expectedClean: '京东', matchWith: '京东', shouldMatch: true },
    { name: '百度网盘超级会员', expectedClean: '百度网盘', matchWith: '百度网盘', shouldMatch: true },
    { name: '随机无关文字', expectedClean: '随机无关文字', matchWith: '腾讯视频', shouldMatch: false }
];

console.log("=== 开始图标匹配逻辑验证 ===");
testCases.forEach(tc => {
    const cleaned = cleanName(tc.name);
    const matched = checkMatch(cleaned, tc.matchWith);
    const status = (cleaned === tc.expectedClean && matched === tc.shouldMatch) ? "✅ 通过" : "❌ 失败";
    console.log(`[${status}] 输入: "${tc.name}" -> 清洗: "${cleaned}" -> 匹配 "${tc.matchWith}": ${matched}`);
});
