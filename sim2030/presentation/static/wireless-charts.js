/* Numeric MATLAB results, rendered locally in the platform theme. No remote assets. */
(function(root){
 'use strict';
 const titles={spectrum:'平均功率谱',search:'PRN 码延迟—多普勒相关搜索图',correlation:'相关峰局部放大切片'};
 function extent(values){let low=Infinity,high=-Infinity;for(const v of values){if(Number.isFinite(v)){low=Math.min(low,v);high=Math.max(high,v);}}return low===Infinity?[0,1]:low===high?[low-1,high+1]:[low,high];}
 function mount(container,data){
  const canvas=document.createElement('canvas'),tip=document.createElement('div');
  canvas.width=1000;canvas.height=450;canvas.tabIndex=0;
  canvas.setAttribute('role','img');canvas.setAttribute('aria-label',titles[data.kind]);
  canvas.className='wireless-chart-canvas';tip.className='wireless-chart-tooltip';tip.hidden=true;
  const reset=document.createElement('button');reset.textContent='重置缩放';reset.type='button';
  const legend=document.createElement('p');legend.className='wireless-note';
  legend.textContent=data.kind==='correlation'?`PRN ${data.prn} · 多普勒 ${data.dopplerHz.toFixed(0)} Hz · 黄色虚线：参考阈值；红点：候选峰`:data.kind==='search'?`PRN ${data.prn} · 红色标记：候选峰`:'';
  container.replaceChildren(canvas,tip,legend,reset);
  const ctx=canvas.getContext('2d');if(!ctx)return;
  const heat=data.kind==='search';
  const xs=heat?data.delayChips:data.kind==='spectrum'?data.frequencyMHz:data.offsetChips;
  const ys=heat?data.frequencyKHz:data.kind==='spectrum'?data.powerDbWPerHz:data.power;
  const full=heat?[0,2046]:extent(xs);let view=full.slice();
  let yr=extent(ys);
  if(heat&&ys.length>1){const half=(ys[1]-ys[0])/2;yr=[yr[0]-half,yr[1]+half];}
  if(!heat){if(data.kind==='correlation'){yr[0]=Math.min(0,yr[0]);yr[1]=Math.max(data.threshold,yr[1]);}const pad=(yr[1]-yr[0])*.08;yr=[yr[0]-pad,yr[1]+pad];}
  const colors=heat?extent(data.scoreDb.flat()):[0,1];
  const box={l:85,t:28,w:heat?790:870,h:345};
  const px=x=>box.l+(x-view[0])/(view[1]-view[0])*box.w;
  const py=y=>box.t+box.h-(y-yr[0])/(yr[1]-yr[0])*box.h;
  function color(value){const t=Math.max(0,Math.min(1,(value-colors[0])/(colors[1]-colors[0])));return `rgb(${Math.round(18+235*t*t)},${Math.round(35+190*t)},${Math.round(75+85*Math.sin(Math.PI*t))})`;}
  function draw(){
   ctx.fillStyle='#102337';ctx.fillRect(0,0,1000,450);ctx.font='18px sans-serif';ctx.lineWidth=1;
   ctx.strokeStyle='#294257';ctx.fillStyle='#a5bbcc';
   for(let i=0;i<=5;i++){
    const x=box.l+i*box.w/5,y=box.t+i*box.h/5;
    ctx.beginPath();ctx.moveTo(x,box.t);ctx.lineTo(x,box.t+box.h);ctx.moveTo(box.l,y);ctx.lineTo(box.l+box.w,y);ctx.stroke();
    ctx.textAlign='center';ctx.fillText((view[0]+i*(view[1]-view[0])/5).toFixed(2),x,box.t+box.h+25);
    ctx.textAlign='right';ctx.fillText((yr[1]-i*(yr[1]-yr[0])/5).toFixed(2),box.l-10,y+5);
   }
   ctx.save();ctx.beginPath();ctx.rect(box.l,box.t,box.w,box.h);ctx.clip();
   if(heat){
    const count=xs.length,rows=ys.length;
    for(let j=0;j<rows;j++)for(let i=0;i<count;i++){
     const x0=2046*i/count,x1=2046*(i+1)/count;
     if(x1<view[0]||x0>view[1])continue;
     ctx.fillStyle=color(data.scoreDb[j][i]);
     ctx.fillRect(px(x0),box.t+box.h*(rows-1-j)/rows,px(x1)-px(x0)+.5,box.h/rows+.5);
    }
    ctx.strokeStyle='#ff7b91';ctx.lineWidth=2;
    const x=px(data.peakDelayChips),y=py(data.peakFrequencyKHz);
    ctx.beginPath();ctx.moveTo(x-7,y-7);ctx.lineTo(x+7,y+7);ctx.moveTo(x-7,y+7);ctx.lineTo(x+7,y-7);ctx.stroke();
   }else{
    ctx.strokeStyle='#55dcec';ctx.lineWidth=2;ctx.beginPath();
    xs.forEach((x,i)=>{if(i===0)ctx.moveTo(px(x),py(ys[i]));else ctx.lineTo(px(x),py(ys[i]));});ctx.stroke();
    if(data.kind==='correlation'){
     ctx.strokeStyle='#f7c76b';ctx.setLineDash([7,5]);ctx.beginPath();ctx.moveTo(box.l,py(data.threshold));ctx.lineTo(box.l+box.w,py(data.threshold));ctx.stroke();ctx.setLineDash([]);
     ctx.fillStyle='#ff7b91';ctx.beginPath();ctx.arc(px(0),py(data.peakScore),5,0,2*Math.PI);ctx.fill();
    }
   }
   ctx.restore();ctx.fillStyle='#bed2e2';ctx.textAlign='center';
   ctx.fillText(heat?'码延迟（码片）':data.kind==='spectrum'?'基带频率（MHz）':'相对相关峰的码延迟（码片）',box.l+box.w/2,425);
   ctx.save();ctx.translate(20,box.t+box.h/2);ctx.rotate(-Math.PI/2);
   ctx.fillText(heat?'多普勒（kHz）':data.kind==='spectrum'?'功率谱密度（dBW/Hz）':'归一化相关功率',0,0);ctx.restore();
   if(heat){
    for(let i=0;i<100;i++){ctx.fillStyle=color(colors[1]-(colors[1]-colors[0])*i/99);ctx.fillRect(905,box.t+i*box.h/100,16,box.h/100+1);}
    ctx.fillStyle='#bed2e2';ctx.textAlign='left';ctx.fillText(colors[1].toFixed(1),928,box.t+12);ctx.fillText(colors[0].toFixed(1),928,box.t+box.h);ctx.fillText('dB',905,box.t-10);
   }
  }
  function local(event){const rect=canvas.getBoundingClientRect();return {x:(event.clientX-rect.left)*1000/rect.width,y:(event.clientY-rect.top)*450/rect.height};}
  canvas.addEventListener('pointermove',event=>{
   const p=local(event);if(p.x<box.l||p.x>box.l+box.w||p.y<box.t||p.y>box.t+box.h){tip.hidden=true;return;}
   const value=view[0]+(p.x-box.l)/box.w*(view[1]-view[0]);let index=0;
   for(let i=1;i<xs.length;i++)if(Math.abs(xs[i]-value)<Math.abs(xs[index]-value))index=i;
   if(heat){const row=Math.min(ys.length-1,Math.max(0,Math.floor((1-(p.y-box.t)/box.h)*ys.length)));tip.textContent=`码延迟 ≈ ${xs[index].toFixed(2)} 码片 · 多普勒 ${ys[row].toFixed(2)} kHz · 分箱峰值 ${data.scoreDb[row][index].toFixed(2)} dB`;}
   else tip.textContent=`${xs[index].toFixed(4)} ${data.kind==='spectrum'?'MHz':'码片'} · ${ys[index].toFixed(4)} ${data.kind==='spectrum'?'dBW/Hz':''}`;
   tip.hidden=false;
  });
  canvas.addEventListener('pointerleave',()=>{tip.hidden=true;});
  canvas.addEventListener('wheel',event=>{
   const p=local(event);if(p.x<box.l||p.x>box.l+box.w)return;event.preventDefault();
   const ratio=(p.x-box.l)/box.w,anchor=view[0]+ratio*(view[1]-view[0]);
   const span=Math.min(full[1]-full[0],Math.max((full[1]-full[0])/100,(view[1]-view[0])*(event.deltaY>0?1.3:.77)));
   const low=Math.max(full[0],Math.min(full[1]-span,anchor-ratio*span));view=[low,low+span];draw();
  },{passive:false});
  reset.onclick=()=>{view=full.slice();tip.hidden=true;draw();};canvas.ondblclick=reset.onclick;
  draw();
 }
 root.WirelessCharts={mount};
})(window);
