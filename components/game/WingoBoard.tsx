'use client';

import { useState, useEffect, useRef } from 'react';
import { useAuth } from '@/lib/firebase/AuthContext';
import { placeBet, settleBet, getBalance } from '@/lib/wallet/engine';
import { generateWingoResult, WINGO_PAYOUTS } from '@/lib/game/wingo/engine';

// Mock data for history/statistics
const MOCK_HISTORY = [
  { period: '20260807100051645', number: 3, color: 'green', size: 'Small' },
  { period: '20260807100051644', number: 8, color: 'violet', size: 'Big' },
  { period: '20260807100051643', number: 1, color: 'green', size: 'Small' },
  { period: '20260807100051642', number: 6, color: 'violet', size: 'Big' },
  { period: '20260807100051641', number: 4, color: 'green', size: 'Small' },
  { period: '20260807100051640', number: 9, color: 'violet', size: 'Big' },
  { period: '20260807100051639', number: 2, color: 'green', size: 'Small' },
  { period: '20260807100051638', number: 7, color: 'violet', size: 'Big' },
  { period: '20260807100051637', number: 5, color: 'violet', size: 'Big' },
  { period: '20260807100051636', number: 0, color: 'green', size: 'Small' },
];

const STATS = {
  numbers: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  missing: [15, 1, 3, 8, 7, 19, 38, 4, 0, 11],
  avgMissing: [11, 7, 6, 7, 10, 9, 13, 9, 5, 6],
  frequency: [7, 11, 12, 11, 8, 9, 6, 9, 15, 12],
  maxConsecutive: [2, 2, 3, 3, 2, 2, 2, 4, 2, 2],
};

export default function WingoBoard() {
  const { user, loading } = useAuth();
  const [balance, setBalance] = useState<number>(0);
  const [timer, setTimer] = useState<number>(15);
  const [period, setPeriod] = useState<string>('20260807100051645');
  const [activeTab, setActiveTab] = useState<'game' | 'history' | 'chart' | 'strategy'>('game');
  
  // Bet Slip State
  const [stake, setStake] = useState<number>(1);
  const [stakeMultiplier, setStakeMultiplier] = useState<number>(1);
  const [selectedColor, setSelectedColor] = useState<'red' | 'green' | 'violet' | null>(null);
  const [selectedNumber, setSelectedNumber] = useState<number | null>(null);
  const [selectedSize, setSelectedSize] = useState<'Big' | 'Small' | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [message, setMessage] = useState('');

  const timerRef = useRef<NodeJS.Timeout | null>(null);

  // Fetch balance
  useEffect(() => {
    if (user) {
      getBalance(user.uid).then(setBalance);
    }
  }, [user]);

  // Timer countdown
  useEffect(() => {
    if (activeTab !== 'game') return;
    timerRef.current = setInterval(() => {
      setTimer((prev) => {
        if (prev <= 1) {
          // Generate new period and reset timer
          setPeriod(`202608071000${String(Math.floor(Math.random() * 100000)).padStart(5, '0')}`);
          setSelectedNumber(null);
          setSelectedColor(null);
          setSelectedSize(null);
          return 15;
        }
        return prev - 1;
      });
    }, 1000);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [activeTab]);

  // --- Betting Logic ---
  const handlePlaceBet = async () => {
    if (!user) { setMessage('Please login'); return; }
    
    // Determine bet type and value
    let betData: any = {};
    let gameType = 'wingo';
    
    if (selectedNumber !== null) {
      betData = { type: 'number', value: selectedNumber };
    } else if (selectedColor) {
      betData = { type: 'color', value: selectedColor };
    } else if (selectedSize) {
      // For Big/Small, we map it to a number range or treat as special
      // Since WINGO engine usually does color/number, we'll handle Big/Small as custom
      // We'll modify the settle logic to interpret Big (5-9) and Small (0-4)
      betData = { type: 'size', value: selectedSize };
    } else {
      setMessage('Select a bet first');
      return;
    }

    const amount = stake * stakeMultiplier;
    if (amount > balance) { setMessage('Insufficient balance'); return; }

    setIsProcessing(true);
    setMessage('');

    try {
      // Place bet
      const { betId, newBalance } = await placeBet(user.uid, 'wingo', amount, betData);
      setBalance(newBalance);

      // Generate result
      const resultData = await generateWingoResult();
      
      // Determine win/loss based on bet type
      let isWin = false;
      let multiplier = 0;
      
      if (betData.type === 'number' && betData.value === resultData.number) {
        isWin = true;
        multiplier = WINGO_PAYOUTS.number;
      } else if (betData.type === 'color' && betData.value === resultData.color) {
        isWin = true;
        multiplier = WINGO_PAYOUTS[resultData.color];
      } else if (betData.type === 'size') {
        const isBig = resultData.number >= 5;
        if ((betData.value === 'Big' && isBig) || (betData.value === 'Small' && !isBig)) {
          isWin = true;
          multiplier = 2; // 2x for Big/Small
        }
      }

      const payout = isWin ? amount * multiplier : 0;

      // Settle bet
      const { newBalance: finalBalance, status } = await settleBet(betId, resultData, payout);
      setBalance(finalBalance);

      if (status === 'won') {
        setMessage(`🎉 Won! ${resultData.color.toUpperCase()} ${resultData.number} (${multiplier}x)`);
      } else {
        setMessage(`😞 Lost. Result: ${resultData.color.toUpperCase()} ${resultData.number}`);
      }

      // Reset selections after bet
      // (Optional: keep them if user wants to bet again)

    } catch (err: any) {
      setMessage('Error: ' + err.message);
    } finally {
      setIsProcessing(false);
    }
  };

  if (loading) return <div className="text-center py-8 text-white">Loading...</div>;

  // --- Render Game UI ---
  return (
    <div className="max-w-4xl mx-auto p-2 text-white pb-20">
      {/* === TOP: Balance & Timer === */}
      <div className="flex justify-between items-center mb-4 bg-[#0f172a] p-3 rounded-xl border border-[#2a2a3a]">
        <div>
          <p className="text-xs text-gray-400">Wallet Balance</p>
          <p className="text-xl font-bold text-green-400">₹{balance.toFixed(2)}</p>
        </div>
        <div className="text-right">
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-400">Time remaining</span>
            <span className="text-2xl font-mono font-bold text-red-500">{String(timer).padStart(2, '0')}</span>
          </div>
          <p className="text-xs text-gray-500">{period}</p>
        </div>
      </div>

      {/* === GAME DURATION TABS === */}
      <div className="flex gap-1 mb-4 bg-[#0f172a] p-1 rounded-xl border border-[#2a2a3a]">
        {['30sec', '1 Min', '3 Min', '5 Min'].map((dur) => (
          <button key={dur} className="flex-1 py-1.5 text-sm font-bold rounded-lg bg-[#1e293b] text-gray-300 active:bg-[#f5c518] active:text-black transition">
            {dur}
          </button>
        ))}
      </div>

      {/* === NUMBER GRID (0-9) === */}
      <div className="mb-4 bg-[#0f172a] p-3 rounded-xl border border-[#2a2a3a]">
        <div className="grid grid-cols-10 gap-1">
          {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((num) => {
            let bg = 'bg-[#1e293b]';
            if (num <= 4) bg = 'bg-green-600/20 hover:bg-green-600/40';
            else bg = 'bg-purple-600/20 hover:bg-purple-600/40';
            const isSelected = selectedNumber === num;
            return (
              <button
                key={num}
                onClick={() => { setSelectedNumber(num); setSelectedColor(null); setSelectedSize(null); }}
                className={`py-3 text-lg font-bold rounded-lg transition border-2 ${isSelected ? 'border-[#f5c518] bg-[#f5c518]/20' : 'border-transparent'} ${bg}`}
              >
                {num}
              </button>
            );
          })}
        </div>
        <div className="flex justify-between mt-2 text-xs">
          <span className="text-green-400">Green (0-4)</span>
          <span className="text-purple-400">Violet (5-9)</span>
        </div>
      </div>

      {/* === COLOR & BIG/SMALL OPTIONS === */}
      <div className="grid grid-cols-5 gap-2 mb-4">
        {['Red', 'Green', 'Violet'].map((color) => (
          <button
            key={color}
            onClick={() => { setSelectedColor(color.toLowerCase() as any); setSelectedNumber(null); setSelectedSize(null); }}
            className={`py-2 rounded-lg font-bold border-2 transition ${selectedColor === color.toLowerCase() ? 'border-[#f5c518] bg-[#f5c518]/20' : 'border-transparent'} bg-[#1e293b]`}
            style={{ color: color === 'Red' ? '#ef4444' : color === 'Green' ? '#22c55e' : '#a855f7' }}
          >
            {color}
          </button>
        ))}
        <button
          onClick={() => { setSelectedSize('Big'); setSelectedNumber(null); setSelectedColor(null); }}
          className={`py-2 rounded-lg font-bold border-2 transition ${selectedSize === 'Big' ? 'border-[#f5c518] bg-[#f5c518]/20' : 'border-transparent'} bg-[#1e293b]`}
        >
          Big
        </button>
        <button
          onClick={() => { setSelectedSize('Small'); setSelectedNumber(null); setSelectedColor(null); }}
          className={`py-2 rounded-lg font-bold border-2 transition ${selectedSize === 'Small' ? 'border-[#f5c518] bg-[#f5c518]/20' : 'border-transparent'} bg-[#1e293b]`}
        >
          Small
        </button>
      </div>

      {/* === BET SLIP (Daman Style) === */}
      <div className="bg-[#0f172a] p-4 rounded-xl border border-[#2a2a3a] mb-4">
        <p className="text-sm font-bold mb-3">WinGo 30sec</p>
        
        {/* Quantity Selector */}
        <div className="flex items-center gap-3 mb-3">
          <span className="text-sm text-gray-400">Quantity</span>
          <div className="flex items-center bg-[#1e293b] rounded-lg overflow-hidden">
            <button onClick={() => setStake(Math.max(1, stake - 1))} className="px-4 py-1 text-xl font-bold hover:bg-[#2a2a3a]">-</button>
            <span className="px-4 py-1 text-lg font-bold">{stake}</span>
            <button onClick={() => setStake(stake + 1)} className="px-4 py-1 text-xl font-bold hover:bg-[#2a2a3a]">+</button>
          </div>
        </div>

        {/* Quick Stake Buttons */}
        <div className="flex gap-2 mb-3">
          {[1, 10, 100, 1000].map((val) => (
            <button key={val} onClick={() => setStake(val)} className="flex-1 py-1 text-sm font-bold bg-[#1e293b] rounded-lg hover:bg-[#2a2a3a]">
              {val}
            </button>
          ))}
        </div>

        {/* Multiplier Chips (X1, X5... these act as stake multipliers) */}
        <div className="flex gap-2 mb-3">
          {[1, 5, 10, 20, 50, 100].map((mult) => (
            <button
              key={mult}
              onClick={() => setStakeMultiplier(mult)}
              className={`flex-1 py-1 text-sm font-bold rounded-lg border transition ${stakeMultiplier === mult ? 'border-[#f5c518] bg-[#f5c518]/10 text-[#f5c518]' : 'border-transparent bg-[#1e293b]'}`}
            >
              X{mult}
            </button>
          ))}
        </div>

        {/* Total & Action */}
        <div className="flex items-center justify-between mt-2 pt-2 border-t border-[#2a2a3a]">
          <div>
            <p className="text-xs text-gray-400">Total amount</p>
            <p className="text-xl font-bold text-green-400">₹{(stake * stakeMultiplier).toFixed(2)}</p>
          </div>
          <div className="flex gap-2">
            <button className="px-4 py-2 text-sm font-bold bg-red-600/80 rounded-lg hover:bg-red-600">Cancel</button>
            <button onClick={handlePlaceBet} disabled={isProcessing} className="px-6 py-2 text-sm font-bold bg-[#f5c518] text-black rounded-lg hover:bg-[#e6b800] disabled:opacity-50">
              {isProcessing ? 'Placing...' : 'Bet'}
            </button>
          </div>
        </div>
        
        {message && <p className={`mt-2 text-sm font-bold ${message.includes('Won') ? 'text-green-400' : 'text-red-400'}`}>{message}</p>}
        <p className="text-[10px] text-gray-500 mt-1 text-center">I agree 《Pre-sale rules》</p>
      </div>

      {/* === TAB: History / Chart / Strategy === */}
      <div className="bg-[#0f172a] rounded-xl border border-[#2a2a3a] overflow-hidden">
        <div className="flex border-b border-[#2a2a3a]">
          <button onClick={() => setActiveTab('game')} className={`flex-1 py-2 text-sm font-bold ${activeTab === 'game' ? 'bg-[#f5c518] text-black' : 'bg-transparent text-gray-400'}`}>Game</button>
          <button onClick={() => setActiveTab('history')} className={`flex-1 py-2 text-sm font-bold ${activeTab === 'history' ? 'bg-[#f5c518] text-black' : 'bg-transparent text-gray-400'}`}>History</button>
          <button onClick={() => setActiveTab('chart')} className={`flex-1 py-2 text-sm font-bold ${activeTab === 'chart' ? 'bg-[#f5c518] text-black' : 'bg-transparent text-gray-400'}`}>Chart</button>
          <button onClick={() => setActiveTab('strategy')} className={`flex-1 py-2 text-sm font-bold ${activeTab === 'strategy' ? 'bg-[#f5c518] text-black' : 'bg-transparent text-gray-400'}`}>Strategy</button>
        </div>

        {/* Content based on tab */}
        <div className="p-3">
          {activeTab === 'game' && <p className="text-xs text-gray-400">Select your bet above.</p>}
          
          {activeTab === 'history' && (
            <div className="space-y-2 max-h-60 overflow-y-auto">
              <p className="text-xs text-gray-400 font-bold">Statistic (last 100 Periods)</p>
              <div className="grid grid-cols-5 gap-1 text-xs">
                {STATS.numbers.map((n, i) => (
                  <div key={i} className="text-center bg-[#1e293b] p-1 rounded">
                    <div>{n}</div>
                    <div className="text-gray-500 text-[10px]">M:{STATS.missing[i]}</div>
                    <div className="text-gray-500 text-[10px]">F:{STATS.frequency[i]}</div>
                  </div>
                ))}
              </div>
              <div className="border-t border-[#2a2a3a] mt-2 pt-2">
                {MOCK_HISTORY.map((item, idx) => (
                  <div key={idx} className="flex justify-between text-xs py-1 border-b border-[#1e293b]">
                    <span className="text-gray-400">{item.period}</span>
                    <span className={`font-bold ${item.color === 'green' ? 'text-green-400' : 'text-purple-400'}`}>{item.number}</span>
                    <span>{item.size}</span>
                    <span className={`w-3 h-3 rounded-full inline-block ${item.color === 'green' ? 'bg-green-400' : 'bg-purple-400'}`}></span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'chart' && (
            <div className="text-center py-4 text-gray-400 text-sm">
              📊 Chart visualization coming soon.
              <br />
              <span className="text-xs text-gray-500">(Trend lines for numbers & colors)</span>
            </div>
          )}

          {activeTab === 'strategy' && (
            <div className="text-center py-4 text-gray-400 text-sm">
              🧠 Follow Strategy
              <br />
              <span className="text-xs text-gray-500">"Five draws in a row with the same result"</span>
              <br />
              <button className="mt-2 px-4 py-1 bg-[#1e293b] rounded-lg text-xs">Enter</button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
