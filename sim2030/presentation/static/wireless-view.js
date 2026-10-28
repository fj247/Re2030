/* Capture status survives browser reload; no client-side waveform fabrication. */
(function(root){
 'use strict';
 const $=id=>document.getElementById(id);
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const phase={queued:'等待计算资源',initializing:'初始化中',generating:'采集中',stopping:'已请求停止',finalizing:'末段收尾／校验中',ready:'数据已就绪',empty:'未产生有效采样',failed:'生成失败',interrupted:'服务曾中断'};
 const analysis={waiting:'等待数据',queued:'等待分析',running:'分析中',complete:'完成',partial:'部分图表失败',failed:'分析失败',not_needed:'无需分析',not_started:'未开始',interrupted:'未确认完成'};
 let snapshot=null, selected=null, loaded=false, inScene=false, polling=false, renderKey=null, followNewest=true;
 async function api(path,body){
  const r=await fetch('/api/wireless'+path,body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const value=await r.json();if(!r.ok||value.error)throw Error(value.error||`HTTP ${r.status}`);return value;
 }
 function notice(text){$('wireless-notice').textContent=text;}
 function render(){
  if(!snapshot)return;
  const tasks=snapshot.tasks;
  $('wireless-recover').hidden=!inScene&&!tasks.length;
  $('wireless-recover').textContent=tasks.some(t=>['queued','initializing','generating','stopping','finalizing'].includes(t.phase))?'检测任务 · 采集未结束':tasks.some(t=>['queued','running'].includes(t.analysis))?'检测任务 · 分析中':'检测节点／历史任务';
  if(followNewest||!selected||!tasks.some(t=>t.id===selected)) selected=tasks[0]?.id;
  const t=tasks.find(t=>t.id===selected);
  const key=JSON.stringify([selected,t,tasks.map(x=>[x.id,x.phase])]);
  if(key===renderKey)return;renderKey=key;
  $('wireless-tasks').innerHTML=`<h3>本轮及历史采集</h3><select id="wireless-history" aria-label="采集任务">${tasks.map(t=>`<option value="${esc(t.id)}" ${t.id===selected?'selected':''}>${esc(new Date(t.created_at).toLocaleString('zh-CN'))} · ${phase[t.phase]||esc(t.phase)}</option>`).join('')}</select>`+(!t?'<p>尚无采集。保存设置后，点选攻击节点并开始攻击。</p>':`
   <div class="wireless-status"><b>${phase[t.phase]||esc(t.phase)}</b><span>图表：${analysis[t.analysis]||esc(t.analysis)}</span></div>
   <p>${t.data_ready?'采集数据已通过校验，可供后续识别读取。':'数据尚未就绪，不作为完整识别输入。'}${t.phase==='ready'&&['complete','partial','failed'].includes(t.analysis)?' 本轮生成与分析处理已结束。':''}</p>
   <dl><dt>执行阶段</dt><dd>${esc(t.stage_detail)}</dd><dt>任务</dt><dd>${esc(t.id)}</dd><dt>检测目录</dt><dd>${esc(t.directory)}</dd><dt>已保存</dt><dd>${(t.bytes/1048576).toFixed(2)} MiB · ${t.files.filter(f=>!f.name.endsWith('.partial')).length} 个已关闭分片 / ${t.files.length} 个文件</dd><dt>实际信号</dt><dd>${Number(t.signal_seconds||0).toFixed(6)} 秒 · ${t.sample_count||0} 复样本</dd><dt>操作经过</dt><dd>${t.wall_seconds!=null?Number(t.wall_seconds).toFixed(1)+' 秒':'采集中／等待开始，尚未结算'}</dd></dl>
   ${t.limit?'<p class="wireless-error">达到本轮存储上限，已停止继续生成。</p>':''}
   ${t.error?`<p class="wireless-error">${esc(t.error)}</p>`:''}${t.analysis_error?`<p class="wireless-error">${esc(t.analysis_error)}</p>`:''}
   <button data-capture-action="stop" ${!['queued','initializing','generating','stopping','finalizing'].includes(t.phase)?'disabled':''}>请求停止采集</button><button data-capture-action="open">打开本轮文件夹</button>
   ${t.data_ready?`<a target="_blank" rel="noopener" href="/api/wireless/tasks/${esc(t.id)}/files/manifest.json">查看识别数据清单</a>`:''}
   <details><summary>分片文件与写入状态</summary><table><thead><tr><th>文件</th><th>大小</th><th>状态</th></tr></thead><tbody>${t.files.map(f=>`<tr><td>${esc(f.name)}</td><td>${(f.bytes/1048576).toFixed(2)} MiB</td><td>${f.ready?'已校验':'写入／待校验'}</td></tr>`).join('')}</tbody></table></details>
   <h3>采集质量与信号结构检查</h3><p class="wireless-note">相关峰仅支持目标 PRN 结构的诊断，不代表身份识别或导航电文解码。</p>
   ${t.analysis_report?.sourceFile?`<p>展示数据：${esc(t.analysis_report.sourceFile)} · ${Number(t.analysis_report.sourceDurationSeconds).toFixed(6)} 秒（首个分片）；${t.analysis_report.presence==='insufficient_samples'?'数据不足 20 毫秒，未进行 PRN 搜索。':'PRN 搜索范围为其中起始 20 毫秒。'}不代表全程统计。</p>`:''}
   ${t.analysis_report?`<p>概览：${esc(({saved:'已保存',failed:'失败'})[t.analysis_report.overview]||t.analysis_report.overview)}；PRN 证据：${esc(({supported_in_tested_windows:'所检窗口支持目标 PRN 结构',inconclusive:'证据不足',insufficient_samples:'采样不足',failed:'分析失败'})[t.analysis_report.presence]||t.analysis_report.presence)}</p>${t.analysis_report.overviewError?`<p class="wireless-error">${esc(t.analysis_report.overviewError)}</p>`:''}${t.analysis_report.presenceError?`<p class="wireless-error">${esc(t.analysis_report.presenceError)}</p>`:''}`:''}
   ${['i_envelope.png','q_envelope.png','mean_psd.png','prn_search.png','correlation.png','overview.png','presence.png'].filter(n=>t.plots.includes(n)).map(name=>`<figure><figcaption>${{'i_envelope.png':'I 分量包络','q_envelope.png':'Q 分量包络','mean_psd.png':'平均功率谱','prn_search.png':'PRN 码延迟—多普勒相关搜索图','correlation.png':'相关峰局部放大切片','overview.png':'历史概览：I/Q 包络、功率与平均频谱','presence.png':'历史 PRN 搜索与对照证据'}[name]}</figcaption><a href="/api/wireless/tasks/${t.id}/files/${name}" target="_blank" rel="noopener"><img alt="${esc(name)}" src="/api/wireless/tasks/${t.id}/files/${name}"></a></figure>`).join('')||'<p>图表尚未生成；采样不足时不伪造分析结果。</p>'}`);
 }
 async function refresh(){
  if(polling)return;polling=true;
  try{snapshot=await api('');if(!loaded){$('wireless-enabled').checked=snapshot.settings.enabled;$('wireless-directory').value=snapshot.settings.output_directory;$('wireless-matlab').value=snapshot.settings.matlab;loaded=true;}render();}
  catch(e){if(!$('wireless-panel').hidden)notice(e.message);}finally{polling=false;}
 }
 function open(){ $('wireless-panel').hidden=false;refresh(); }
 function scene(enabled){const leaving=inScene&&!enabled;inScene=enabled;if(leaving)$('wireless-panel').hidden=true;if(snapshot)render();}
 function bind(){
  $('wireless-close').onclick=()=>{$('wireless-panel').hidden=true;};$('wireless-recover').onclick=open;
  $('wireless-settings').onsubmit=async event=>{event.preventDefault();try{snapshot=await api('/settings',{enabled:$('wireless-enabled').checked,output_directory:$('wireless-directory').value.trim(),matlab:$('wireless-matlab').value.trim()});notice('设置已保存；仅手动开始授时攻击时启动生成。');render();}catch(e){notice(e.message);}};
  $('wireless-pick').onclick=async()=>{notice('请在本机目录选择窗口中选择位置；窗口可能位于浏览器后方。');try{const r=await api('/pick-directory',{});if(r.path)$('wireless-directory').value=r.path;notice(r.path?'目录已选择，请保存设置。':'已取消选择。');}catch(e){notice(e.message);}};
  $('wireless-tasks').addEventListener('change',event=>{if(event.target.id==='wireless-history'){selected=event.target.value;followNewest=selected===snapshot.tasks[0]?.id;render();}});
  $('wireless-tasks').addEventListener('click',async event=>{const action=event.target.dataset.captureAction;if(!action||!selected)return;try{await api(`/tasks/${selected}/${action}`,{});await refresh();notice(action==='stop'?'已请求停止；将完成文件收尾。':'已请求打开本轮文件夹。');}catch(e){notice(e.message);}});
  let drag;const panel=$('wireless-panel'),handle=$('wireless-handle');
  handle.addEventListener('pointerdown',e=>{if(e.target.closest('button')||e.button!==0)return;const b=panel.getBoundingClientRect();drag={x:e.clientX,y:e.clientY,left:b.left,top:b.top};handle.setPointerCapture(e.pointerId);});
  handle.addEventListener('pointermove',e=>{if(!drag)return;panel.style.left=Math.max(0,Math.min(innerWidth-panel.offsetWidth,drag.left+e.clientX-drag.x))+'px';panel.style.top=Math.max(0,Math.min(innerHeight-40,drag.top+e.clientY-drag.y))+'px';panel.style.right='auto';});
  handle.addEventListener('pointerup',()=>{drag=null;});handle.addEventListener('pointercancel',()=>{drag=null;});
  refresh();setInterval(refresh,1500);
 }
 root.WirelessView={open,scene,bind};
})(window);
