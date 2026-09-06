"use client";
import { useEffect, useState, useCallback } from "react";
import { api } from "@/lib/api";

function Card({ card }: { card: string }) {
  if (!card || card === "??" || card.length < 2) return <span className="inline-block w-10 h-14 bg-gradient-to-br from-red-800 to-red-950 rounded-md border border-yellow-700 text-center leading-[56px] text-yellow-600 text-xs font-bold shadow-md">♠</span>;
  const suits: Record<string,string> = {h:"♥",d:"♦",c:"♣",s:"♠"};
  const ranks: Record<string,string> = {T:"10",J:"J",Q:"Q",K:"K",A:"A"};
  const r = ranks[card[0]] || card[0], s = suits[card[1]] || card[1];
  const red = card[1]==="h"||card[1]==="d";
  return <span className={`inline-flex flex-col items-center justify-center w-10 h-14 bg-white rounded-md border border-gray-200 shadow-md font-bold ${red?"text-red-600":"text-gray-900"}`}>
    <span className="text-sm leading-none">{r}</span><span className="text-xs leading-none">{s}</span>
  </span>;
}

export default function LiveGamesPage() {
  const [rooms, setRooms] = useState<any[]>([]);
  const [sel, setSel] = useState<any>(null);
  const [selId, setSelId] = useState<string|null>(null);
  const [auto, setAuto] = useState(true);
  const [pollIntervalSec, setPollIntervalSec] = useState<number|null>(null);

  const load = useCallback(async()=>{try{const d=await api("/api/game-admin/rooms");setRooms(d.rooms||[]);}catch{setRooms([]);}}, []);
  const loadRoom = useCallback(async(id:string)=>{try{const d=await api(`/api/game-admin/rooms/${id}`);setSel(d);setSelId(id);}catch{}}, []);

  useEffect(()=>{
    api("/api/settings/game-runtime").then(config=>setPollIntervalSec(config.admin_live_poll_interval_sec)).catch(()=>{});
  },[]);

  useEffect(()=>{
    load();
    if(!auto || pollIntervalSec===null)return;
    const t=setInterval(()=>{load();if(selId)loadRoom(selId);},pollIntervalSec*1000);
    return()=>clearInterval(t);
  },[auto,selId,pollIntervalSec,load,loadRoom]);

  const players = sel ? Object.entries(sel.players||{}) as [string,any][] : [];

  return <div>
    <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mb-6">
      <h1 className="text-2xl font-bold text-yellow-400">🎮 Live Game Monitor</h1>
      <div className="flex items-center gap-3">
        <label className="flex items-center gap-2 text-sm text-yellow-400/60 cursor-pointer">
          <input type="checkbox" checked={auto} onChange={e=>setAuto(e.target.checked)} className="accent-green-500"/>Auto {pollIntervalSec?`(${pollIntervalSec}s)`:""}
        </label>
        <button onClick={load} className="bg-yellow-600 hover:bg-yellow-500 text-black px-4 py-2 rounded text-sm font-bold">🔄</button>
      </div>
    </div>

    <details className="mb-4 text-xs text-sun-gold/50 bg-sun-black/30 rounded-lg p-3">
      <summary className="cursor-pointer text-sun-gold/70 font-bold">ℹ️ วิธีใช้งานหน้านี้</summary>
      <div className="mt-2 space-y-1">
        <p>📋 <b>หน้านี้คืออะไร:</b> ดูเกมที่กำลังเล่นอยู่ตอนนี้แบบ Realtime (อัปเดตทุก 1 วินาที)</p>
        <p>👁 <b>ข้อมูลที่เห็น:</b></p>
        <p className="pl-4">• ไพ่ในมือของทุกคน (Admin เห็นหมด)</p>
        <p className="pl-4">• ไพ่กลางโต๊ะ (Community Cards)</p>
        <p className="pl-4">• เงินในกองกลาง (Pot)</p>
        <p className="pl-4">• ใครกำลังเป็นเทิร์น (มีสัญลักษณ์ ⏱ กะพริบ)</p>
        <p className="pl-4">• Action Log = บันทึกการกระทำ (Fold/Call/Raise)</p>
        <p>🔍 <b>วิธีใช้:</b> คลิกที่ห้องในรายการด้านบน → จะแสดงโต๊ะเกมด้านล่าง</p>
        <p>💡 <b>ใช้ทำอะไร:</b> ตรวจสอบการเล่น, ดูว่ามีพฤติกรรมผิดปกติไหม (เช่น สมรู้ร่วมคิด)</p>
      </div>
    </details>

    {/* Room cards */}
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
      {rooms.length===0 ? <div className="col-span-3 text-center py-12 text-yellow-400/30"><p className="text-4xl mb-2">🎰</p><p>ไม่มีห้องที่กำลังเล่น</p></div>
      : rooms.map(r=><div key={r.tableId} onClick={()=>loadRoom(r.tableId)}
        className={`cursor-pointer rounded-xl p-4 border-2 transition-all ${selId===r.tableId?"border-yellow-400 bg-yellow-400/10":"border-yellow-400/20 bg-black/40 hover:border-yellow-400/50"}`}>
        <div className="flex justify-between items-center mb-2">
          <span className="text-white font-bold text-sm">Room {r.tableId?.substring(0,8)}</span>
          <span className={`text-xs px-2 py-1 rounded ${r.isPlaying?"bg-green-600 text-white":"bg-yellow-600 text-black"}`}>{r.isPlaying?"🟢 LIVE":"🟡 WAIT"}</span>
        </div>
        <div className="flex justify-between text-xs text-yellow-400/60">
          <span>👥 {Object.keys(r.players||{}).length}</span><span>💰 {r.pot}</span><span>🃏 {r.currentRound||"—"}</span>
        </div>
      </div>)}
    </div>

    {/* Visual table view */}
    {sel && <div className="bg-gradient-to-b from-red-950/80 to-black/90 rounded-2xl border border-yellow-400/30 p-6 relative overflow-hidden">
      {/* Header */}
      <div className="flex justify-between items-center mb-4">
        <div>
          <h2 className="text-xl font-bold text-yellow-400">👁 Live Table — {selId?.substring(0,8)}</h2>
          <div className="flex gap-4 text-xs text-yellow-400/50 mt-1">
            <span>Round: <b className="text-white uppercase">{sel.currentRound||"—"}</b></span>
            <span>Hand: <b className="text-white">#{sel.handNumber}</b></span>
            <span>Dealer: <b className="text-white">Seat {sel.dealerSeat}</b></span>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <span className={`text-sm px-3 py-1 rounded-full font-bold ${sel.isPlaying?"bg-green-600 text-white animate-pulse":"bg-yellow-600 text-black"}`}>{sel.isPlaying?"🟢 LIVE":"🟡 WAITING"}</span>
          <button onClick={()=>{setSel(null);setSelId(null);}} className="text-yellow-400/40 hover:text-white text-xl">✕</button>
        </div>
      </div>

      {/* Poker table visual */}
      <div className="relative w-full max-w-[600px] mx-auto aspect-[600/380]">
        {/* Table oval */}
        <div className="absolute inset-0 rounded-[50%] bg-gradient-to-b from-yellow-900/40 to-yellow-950/60 border-4 border-yellow-600/60 shadow-2xl"/>
        <div className="absolute inset-2 rounded-[50%] bg-gradient-radial from-red-800 via-red-900 to-red-950 border border-yellow-600/20"/>
        <div className="absolute inset-6 rounded-[50%] border border-yellow-600/15"/>

        {/* POT center */}
        <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 text-center">
          <div className="bg-black/60 rounded-xl px-4 py-2">
            <p className="text-yellow-400/50 text-xs">POT</p>
            <p className="text-yellow-400 font-bold text-2xl">{sel.pot} 🪙</p>
          </div>
          {/* Last result banner */}
          {sel.lastResult && !sel.isPlaying && <div className="mt-2 bg-black/80 rounded-lg px-3 py-2 animate-pulse">
            <p className="text-green-400 font-bold text-sm">🏆 Winner: {sel.lastResult.winners?.map((w:any)=>w.username).join(', ')}</p>
            <p className="text-yellow-400 text-xs">+{sel.lastResult.prizePerWinner} 🪙 each</p>
          </div>}
        </div>

        {/* Community cards */}
        {sel.communityCards?.length > 0 && <div className="absolute left-1/2 -translate-x-1/2 top-[38%] flex gap-1">
          {sel.communityCards.map((c:string,i:number)=><Card key={i} card={c}/>)}
        </div>}

        {/* Players around table */}
        {(()=>{
          const positions = [
            {left:'72%',top:'55%'},{left:'72%',top:'20%'},{left:'50%',top:'2%'},{left:'18%',top:'2%'},
            {left:'5%',top:'20%'},{left:'5%',top:'55%'},{left:'18%',top:'80%'},{left:'55%',top:'80%'},{left:'38%',top:'88%'},
          ];
          return players.map(([seat,p]:any,idx:number)=>{
            const pos = positions[idx%positions.length];
            const isTurn = sel.currentPlayerSeat?.toString()===seat;
            return <div key={seat} className="absolute -translate-x-1/2 -translate-y-1/2" style={{left:pos.left,top:pos.top}}>
              <div className={`flex flex-col items-center ${isTurn?'scale-110':''} transition-transform`}>
                {/* Avatar */}
                {(()=>{
                  const isWinner = sel.lastResult && !sel.isPlaying && sel.lastResult.winners?.some((w:any)=>w.seat?.toString()===seat);
                  const isLoser = sel.lastResult && !sel.isPlaying && sel.lastResult.losers?.some((w:any)=>w.seat?.toString()===seat);
                  return <div className={`w-12 h-12 rounded-full border-3 flex items-center justify-center text-lg font-bold relative
                    ${isWinner?'border-green-400 bg-green-400/20 shadow-lg shadow-green-400/40':
                      isLoser?'border-red-500 bg-red-500/10 opacity-50':
                      isTurn?'border-amber-400 bg-amber-400/20 shadow-lg shadow-amber-400/30 animate-pulse':
                      'border-yellow-600 bg-black/60'} ${p.folded?'opacity-40':''}`}>
                    {p.folded?'✕':seat}
                    {isWinner&&<span className="absolute -top-2 -right-2 text-lg">🏆</span>}
                    {isLoser&&!p.folded&&<span className="absolute -top-2 -right-2 text-sm">❌</span>}
                  </div>;
                })()}
                {/* Name + chips */}
                <div className="bg-black/80 rounded px-2 py-0.5 mt-1 text-center min-w-[70px]">
                  <p className="text-white text-[10px] font-bold truncate">{p.username||`Seat ${seat}`}</p>
                  <p className="text-yellow-400 text-[9px]">${p.chips} {isTurn&&<span className="text-amber-400 animate-pulse">⏱</span>}</p>
                  {p.currentBet>0&&<p className="text-orange-400 text-[8px]">Bet: {p.currentBet}</p>}
                </div>
                {/* Cards - Admin sees ALL */}
                <div className="flex gap-0.5 mt-1">
                  {(p.holeCards||[]).map((c:string,i:number)=><Card key={i} card={c}/>)}
                  {(!p.holeCards||p.holeCards.length===0)&&<span className="text-yellow-400/20 text-[8px]">—</span>}
                </div>
                {/* Status badges */}
                <div className="flex gap-1 mt-0.5">
                  {p.folded&&<span className="text-[8px] bg-red-700 text-white px-1 rounded">FOLD</span>}
                  {p.allIn&&<span className="text-[8px] bg-purple-600 text-white px-1 rounded">ALL-IN</span>}
                  {sel.dealerSeat?.toString()===seat&&<span className="text-[8px] bg-blue-600 text-white px-1 rounded">D</span>}
                  {sel.lastResult&&!sel.isPlaying&&sel.lastResult.winners?.some((w:any)=>w.seat?.toString()===seat)&&<span className="text-[8px] bg-green-500 text-white px-1 rounded animate-pulse">🏆 WIN</span>}
                  {sel.lastResult&&!sel.isPlaying&&sel.lastResult.losers?.some((w:any)=>w.seat?.toString()===seat)&&!p.folded&&<span className="text-[8px] bg-red-600 text-white px-1 rounded">LOST</span>}
                </div>
              </div>
            </div>;
          });
        })()}
      </div>

      {/* Refresh + Action Log */}
      <div className="mt-4 flex gap-4">
        <div className="flex-1">
          <p className="text-yellow-400/60 text-xs font-bold mb-2">📋 Action Log (realtime)</p>
          <div className="bg-black/60 rounded-lg p-3 max-h-32 overflow-y-auto text-xs space-y-1">
            {(sel.actions||[]).length === 0 ? <p className="text-yellow-400/20">No actions yet</p>
            : [...(sel.actions||[])].reverse().map((a:any,i:number)=>
              <div key={i} className="flex gap-2">
                <span className="text-yellow-400/40">{a.round}</span>
                <span className="text-white">Seat {a.seat}</span>
                <span className={`font-bold ${a.action==='fold'?'text-red-400':a.action==='raise'||a.action==='all_in'?'text-orange-400':'text-green-400'}`}>{a.action.toUpperCase()}</span>
                {a.amount>0&&<span className="text-yellow-400">{a.amount}🪙</span>}
              </div>)}
          </div>
        </div>
        <div className="text-center pt-6">
          <button onClick={()=>selId&&loadRoom(selId)} className="bg-yellow-600 hover:bg-yellow-500 text-black px-6 py-2 rounded font-bold text-sm">🔄 Refresh</button>
          <p className="text-yellow-400/30 text-xs mt-1">Auto-refresh {pollIntervalSec?`every ${pollIntervalSec}s`:"from server config"}</p>
        </div>
      </div>
    </div>}
  </div>;
}
