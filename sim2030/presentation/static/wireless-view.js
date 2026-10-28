/* Capture status survives browser reload; no client-side waveform fabrication. */
(function(root){
 'use strict';
 const $=id=>document.getElementById(id);
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const phase={queued:'等待计算资源',initializing:'初始化中',generating:'采集中',stopping:'已请求停止',finalizing:'末段收尾／校验中',ready:'数据已就绪',empty:'未产生有效采样',failed:'生成失败',interrupted:'服务曾中断'};
 const analysis={waiting:'等待数据',queued:'等待分析',running:'分析中',complete:'完成',partial:'部分图表失败',failed:'分析失败',not_needed:'无需分析',not_started:'未开始',interrupted:'未确认完成'};
 const chartCache=new Map();
 const chartNames={'mean_psd.json':['spectrum','平均功率谱'],'prn_search.json':['search','PRN 码延迟—多普勒相关搜索图'],'correlation.json':['correlation','相关峰局部放大切片']};
 let chartKey=null;
 let snapshot=null, selected=null, loaded=false, inScene=false, polling=false, renderKey=null, followNewest=true;
 async function api(path,body){
  const r=await fetch('/api/wireless'+path,body===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const value=await r.json();if(!r.ok||value.error)throw Error(value.error||`HTTP ${r.status}`);return value;
 }
 function notice(text){$('wireless-notice').textContent=text;}
 function mountCharts(task){
  for(const name of task.charts||[]){
   if(!chartNames[name])continue;
   const [kind]=chartNames[name],url=`/api/wireless/tasks/${task.id}/files/${name}`;
   const element=$('wireless-chart-'+kind);if(!element)continue;
   if(!chartCache.has(url)){
    if(chartCache.size>=24)chartCache.delete(chartCache.keys().next().value);
    const pending=fetch(url).then(async r=>{if(!r.ok)throw Error('图表数据暂不可用');return r.json();});
    chartCache.set(url,pending);
   }
   chartCache.get(url).then(data=>{
    if(selected===task.id&&$('wireless-chart-'+kind)===element)root.WirelessCharts.mount(element,data);
   }).catch(error=>{chartCache.delete(url);if($('wireless-chart-'+kind)===element)element.textContent=error.message;});
  }
 }
 function chartMarkup(task){
  const charts=(task.charts||[]).filter(name=>chartNames[name]);
  const legacy=['mean_psd.png','prn_search.png','correlation.png'].filter(name=>(task.plots||[]).includes(name)&&!charts.includes(name.replace('.png','.json')));
  return charts.map(name=>{const [kind,title]=chartNames[name];return `<figure class="wireless-chart-card"><figcaption>${title}</figcaption><div id="wireless-chart-${kind}" class="wireless-chart">正在绘制…</div></figure>`;}).join('')+
   legacy.map(name=>`<figure class="wireless-chart-card"><figcaption>${{'mean_psd.png':'平均功率谱','prn_search.png':'PRN 码延迟—多普勒相关搜索图','correlation.png':'相关峰局部放大切片'}[name]}（历史图片）</figcaption><a href="/api/wireless/tasks/${task.id}/files/${name}" target="_blank" rel="noopener"><img alt="${esc(name)}" src="/api/wireless/tasks/${task.id}/files/${name}"></a></figure>`).join('')+
   (!charts.length&&!legacy.length?'<p>等待首个分片完成；图表将在计算完成后分别显示。</p>':'')+
   (charts.length?'<p class="wireless-note">悬停查看数值，滚轮缩放横轴，双击或点击按钮重置缩放。搜索图按延迟分箱保留峰值，标记显示精确峰位置。</p>':'');
 }
 function reportMarkup(report){
  if(!report)return '';
  const labels={saved:'已生成',pending:'计算中',failed:'失败',insufficient_samples:'采样不足'};
  const source=report.sourceFile?`<p>展示数据：${esc(report.sourceFile)} · ${Number(report.sourceDurationSeconds).toFixed(6)} 秒（首个分片）；${report.presence==='insufficient_samples'?'数据不足 20 毫秒，未进行 PRN 搜索。':'PRN 搜索范围为其中起始 20 毫秒。'}</p>`:'';
  return source+`<p>平均功率谱：${esc(labels[report.spectrum||report.overview]||'等待数据')}；相关搜索图：${esc(labels[report.search]||'等待数据')}；相关峰切片：${esc(labels[report.correlation]||'等待数据')}</p><p>PRN 证据：${esc(({supported_in_tested_windows:'所检窗口支持目标 PRN 结构',inconclusive:'证据不足',insufficient_samples:'采样不足',failed:'分析失败',pending:'分析中'})[report.presence]||report.presence)}</p>${report.overviewError?`<p class="wireless-error">${esc(report.overviewError)}</p>`:''}${report.presenceError?`<p class="wireless-error">${esc(report.presenceError)}</p>`:''}`;
 }
 function render(){
  if(!snapshot)return;
  const tasks=snapshot.tasks;
  $('wireless-receiver').textContent=snapshot.receiver?.detail||'';
  $('wireless-recover').hidden=!inScene&&!tasks.length;
  $('wireless-recover').textContent=tasks.some(t=>['queued','initializing','generating','stopping','finalizing'].includes(t.phase))?'检测任务 · 采集未结束':tasks.some(t=>['queued','running'].includes(t.analysis))?'检测任务 · 分析中':'检测节点／历史任务';
  if(followNewest||!selected||!tasks.some(t=>t.id===selected)) selected=tasks[0]?.id;
  const t=tasks.find(t=>t.id===selected);
  const key=JSON.stringify([selected,t,tasks.map(x=>[x.id,x.phase])]);
  if(key===renderKey)return;renderKey=key;
  const previousRegion=$('wireless-chart-region');
  const nextChartKey=JSON.stringify([t?.id,t?.charts,t?.plots]);
  $('wireless-tasks').innerHTML=`<h3>本轮及历史采集</h3><select id="wireless-history" aria-label="采集任务">${tasks.map(t=>`<option value="${esc(t.id)}" ${t.id===selected?'selected':''}>${esc(new Date(t.created_at).toLocaleString('zh-CN'))} · ${phase[t.phase]||esc(t.phase)}</option>`).join('')}</select>`+(!t?'<p>尚无采集。保存设置后，点选攻击节点并开始攻击。</p>':`
   <div class="wireless-status"><b>${phase[t.phase]||esc(t.phase)}</b><span>图表：${analysis[t.analysis]||esc(t.analysis)}</span></div>
   <p>${t.data_ready?'采集数据已通过校验，可供后续识别读取。':'数据尚未就绪，不作为完整识别输入。'}${t.phase==='ready'&&['complete','partial','failed'].includes(t.analysis)?' 本轮生成与分析处理已结束。':''}</p>
   <dl><dt>执行阶段</dt><dd>${esc(t.stage_detail)}</dd><dt>任务</dt><dd>${esc(t.id)}</dd><dt>检测目录</dt><dd>${esc(t.directory)}</dd><dt>已保存</dt><dd>${(t.bytes/1048576).toFixed(2)} MiB · ${t.files.filter(f=>!f.name.endsWith('.partial')).length} 个已关闭分片 / ${t.files.length} 个文件</dd><dt>实际信号</dt><dd>${Number(t.signal_seconds||0).toFixed(6)} 秒 · ${t.sample_count||0} 复样本</dd><dt>操作经过</dt><dd>${t.wall_seconds!=null?Number(t.wall_seconds).toFixed(1)+' 秒':'采集中／等待开始，尚未结算'}</dd></dl>
   ${t.limit?'<p class="wireless-error">达到本轮存储上限，已停止继续生成。</p>':''}
   ${t.error?`<p class="wireless-error">${esc(t.error)}</p>`:''}${t.analysis_error?`<p class="wireless-error">${esc(t.analysis_error)}</p>`:''}
   <button data-capture-action="stop" ${!['queued','initializing','generating','stopping','finalizing'].includes(t.phase)?'disabled':''}>请求停止采集</button><button data-capture-action="open">打开本轮文件夹</button>
   ${t.data_ready?`<a target="_blank" rel="noopener" href="/api/wireless/tasks/${esc(t.id)}/files/manifest.json">查看识别数据清单</a>`:''}
   <details><summary>分片文件与写入状态</summary><table><thead><tr><th>文件</th><th>大小</th><th>状态</th></tr></thead><tbody>${t.files.map(f=>`<tr><td>${esc(f.name)}</td><td>${(f.bytes/1048576).toFixed(2)} MiB</td><td>${f.ready?'已校验':'写入／待校验'}</td></tr>`).join('')}</tbody></table></details>
   <h3>采集质量与信号结构检查</h3><p class="wireless-note">相关峰仅支持目标 PRN 结构的诊断。</p>
   ${reportMarkup(t.analysis_report)}
   <div id="wireless-chart-region">${chartMarkup(t)}</div>`);
  if(t){
   if(chartKey===nextChartKey&&previousRegion)$('wireless-chart-region').replaceWith(previousRegion);
   else mountCharts(t);
  }
  chartKey=nextChartKey;
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
  $('wireless-settings').onsubmit=async event=>{event.preventDefault();try{snapshot=await api('/settings',{enabled:$('wireless-enabled').checked,output_directory:$('wireless-directory').value.trim(),matlab:$('wireless-matlab').value.trim()});notice('设置已保存；启用采集后将准备接收装置，就绪后可手动开始攻击。');render();}catch(e){notice(e.message);}};
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
