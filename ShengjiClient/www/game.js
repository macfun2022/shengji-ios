/* =========================================================================
 * 升级（ShengJi）规则引擎 —— 单副54张·4人·局域网
 * 纯逻辑模块，无网络依赖。可在 Node 与浏览器共用。
 *
 * 牌构成：54 = 52 标准 + 大小王(大猫/小猫)
 *   - 主( trump ) 18 张：大猫、小猫、主令(当前级数在主营的花色)、
 *     3 个副令(当前级数在其余三门花色)、主营其余 A K Q J 10 9 8 7 6 5 4 3 2
 *   - 副( side ) 3 门 × 12 张
 *
 * 分牌：5=5分，10=10分，K=10分（共 100 分）
 * 升级映射（按防守方/对家吃到的分数 defenderPoints）：
 *   0      -> 庄家方升 3 级
 *   5..39  -> 庄家方赢（级数不变）
 *   40..55 -> 对家方赢（级数不变）
 *   60..75 -> 对家方升 1 级
 *   80..95 -> 对家方升 2 级
 *   100    -> 对家方升 3 级
 * （分数只可能是 5 的倍数，因此上述区间天然连续无遗漏）
 * ========================================================================= */

const SUITS = ['♠', '♥', '♦', '♣']; // ♠ > ♥ > ♦ > ♣ （仅用于副令之间、同点比大小）
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const RANK_VALUE = { '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14 };
const BJ = 'BJ'; // 大猫 big joker
const SJ = 'SJ'; // 小猫 small joker

function pointOf(rank) {
  if (rank === '5') return 5;
  if (rank === '10' || rank === 'K') return 10;
  return 0;
}

/* 生成一副 54 张 */
function buildDeck() {
  const deck = [];
  let id = 0;
  for (const suit of SUITS) {
    for (const rank of RANKS) {
      deck.push({ id: `c${id++}`, suit, rank, isJoker: false, point: pointOf(rank) });
    }
  }
  deck.push({ id: `c${id++}`, suit: null, rank: BJ, isJoker: true, point: 0, joker: 'big' });
  deck.push({ id: `c${id++}`, suit: null, rank: SJ, isJoker: true, point: 0, joker: 'small' });
  return deck;
}

function cardLabel(card) {
  if (card.isJoker) return card.joker === 'big' ? '大猫' : '小猫';
  return card.suit + card.rank;
}

/* 是否为“当前级数”的牌（用于亮主/主令判定） */
function isLevelCard(card, levelRank) {
  return !card.isJoker && card.rank === levelRank;
}

/* 该牌是否为主 */
function isTrump(card, trumpSuit, levelRank) {
  if (card.isJoker) return true;
  if (card.rank === levelRank) return true;       // 主令 + 3 副令
  if (trumpSuit && card.suit === trumpSuit) return true;
  return false;
}

/* 主牌内部大小（越大越强）。副牌不参与此比较。 */
function trumpOrder(card, trumpSuit, levelRank) {
  // 大猫 > 小猫 > 主令 > 3副令(按花色 ♠>♥>♦>♣) > 主营 A..2
  if (card.isJoker) return card.joker === 'big' ? 1000 : 999;
  if (card.rank === levelRank) {
    if (card.suit === trumpSuit) return 998; // 主令
    const sIdx = SUITS.indexOf(card.suit); // 3 副令
    return 900 - sIdx; // ♠(0)->900, ♥(1)->899, ♦(2)->898, ♣(3)->897
  }
  // 主营普通牌：用点数，但需低于副令(>=897)。A=14...2=2，加基准 100 保证高于副牌
  return 100 + RANK_VALUE[card.rank];
}

/* 一副牌里某张牌的“强度值”：用于在同一花色/主内比较 */
function strengthOf(card, trumpSuit, levelRank) {
  if (isTrump(card, trumpSuit, levelRank)) return trumpOrder(card, trumpSuit, levelRank);
  return RANK_VALUE[card.rank]; // 副牌用点数
}

/* 两张同“类”牌比较：返回 >0 表示 a 强，<0 表示 b 强。
 * 注意：主永远大于副，由调用方先按类别分流。 */
function cmpCard(a, b, trumpSuit, levelRank) {
  return strengthOf(a, trumpSuit, levelRank) - strengthOf(b, trumpSuit, levelRank);
}

/* 判断某次出牌是否合法（跟牌规则）
 * plays: 本 trick 已出的牌 [{seat, card}]（按出牌顺序）
 * hand: 当前玩家手牌
 * card: 拟出的牌
 */
function isLegalPlay(hand, plays, card, trumpSuit, levelRank) {
  if (!hand.find((c) => c.id === card.id)) return false; // 必须手里真有
  if (plays.length === 0) return true; // 首家随便出

  const lead = plays[0].card;
  const leadIsTrump = isTrump(lead, trumpSuit, levelRank);
  const leadSuit = lead.suit;

  if (leadIsTrump) {
    // 首家出主：有主必须跟主，无主可贴副
    const hasTrump = hand.some((c) => isTrump(c, trumpSuit, levelRank));
    if (hasTrump && !isTrump(card, trumpSuit, levelRank)) return false;
    return true;
  }
  // 首家出副花色
  const hasLeadSuit = hand.some((c) => !c.isJoker && c.suit === leadSuit);
  if (hasLeadSuit) {
    // 有该花色必须跟该花色（即使该花色牌恰好是级牌也算该花色）
    if (!(card.suit === leadSuit)) return false;
    return true;
  }
  // 没有该花色：可出主杀，也可贴任意副牌
  return true;
}

/* 结算一墩：返回赢家座位与这墩总分 */
function resolveTrick(plays, trumpSuit, levelRank) {
  const lead = plays[0].card;
  const leadIsTrump = isTrump(lead, trumpSuit, levelRank);
  const leadSuit = lead.suit;

  const trumps = plays.filter((p) => isTrump(p.card, trumpSuit, levelRank));
  let winner;
  if (trumps.length > 0) {
    winner = trumps.reduce((best, p) =>
      cmpCard(p.card, best.card, trumpSuit, levelRank) > 0 ? p : best
    );
  } else {
    // 全是副牌，按首家花色比大小
    const inSuit = plays.filter((p) => !p.card.isJoker && p.card.suit === leadSuit);
    winner = inSuit.reduce((best, p) =>
      cmpCard(p.card, best.card, trumpSuit, levelRank) > 0 ? p : best
    );
  }
  const points = plays.reduce((s, p) => s + (p.card.point || 0), 0);
  return { winnerSeat: winner.seat, points };
}

/* 升级映射：输入防守方吃到的总分，返回 {advancing, steps, note} */
function levelOutcome(defenderPoints) {
  if (defenderPoints === 0) return { advancing: 'dealer', steps: 3, note: '对家 0 分，庄家升 3 级' };
  if (defenderPoints <= 39) return { advancing: 'dealer', steps: 0, note: '对家不足 40 分，庄家赢（级数不变）' };
  if (defenderPoints <= 55) return { advancing: 'defender', steps: 0, note: '对家 40–55 分赢，级数不变' };
  if (defenderPoints <= 75) return { advancing: 'defender', steps: 1, note: '对家 60–75 分，升 1 级' };
  if (defenderPoints <= 95) return { advancing: 'defender', steps: 2, note: '对家 80–95 分，升 2 级' };
  return { advancing: 'defender', steps: 3, note: '对家 100 分，升 3 级' };
}

/* 级数推进：'2'->'3'->...->'A'->'2' 循环 */
function advanceLevel(levelRank, steps) {
  let idx = RANKS.indexOf(levelRank);
  idx = (idx + steps) % RANKS.length;
  if (idx < 0) idx += RANKS.length;
  return RANKS[idx];
}

/* 洗牌（Fisher-Yates），可注入 rng 便于测试 */
function shuffle(arr, rng) {
  rng = rng || Math.random;
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/* 把一副牌切成：4 手 ×12 + 底牌 6 */
function deal(deck) {
  const hands = [[], [], [], []];
  for (let i = 0; i < 48; i++) hands[i % 4].push(deck[i]);
  const kitty = deck.slice(48, 54);
  return { hands, kitty };
}

/* 底牌校验：6 张底牌不能含 5/10/K 分牌 */
function kittyHasScore(kitty) {
  return kitty.some((c) => c.point > 0);
}

/* 合作伙伴：座位 0,1,2,3 顺时针，伙伴为对面 (i+2)%4 */
function partnerOf(seat) {
  return (seat + 2) % 4;
}
function isSameTeam(a, b) {
  return partnerOf(a) === b;
}

/* 亮主优先级：单张级牌=1，对子级牌=2（抢亮时高优先级覆盖低优先级） */
function bidPriority(cards) {
  if (cards.length === 2 && cards[0].rank === cards[1].rank && cards[0].suit === cards[1].suit) return 2;
  return 1;
}

const Game = {
  SUITS, RANKS, RANK_VALUE, BJ, SJ,
  pointOf, buildDeck, cardLabel, isLevelCard, isTrump, trumpOrder, strengthOf,
  cmpCard, isLegalPlay, resolveTrick, levelOutcome, advanceLevel,
  shuffle, deal, kittyHasScore, partnerOf, isSameTeam, bidPriority,
};

if (typeof module !== 'undefined' && module.exports) module.exports = Game;
if (typeof window !== 'undefined') window.Game = Game;
