/* ---- deterministic timeline harness ----
   A draft defines: window.DRAFT = { title, subtitle, duration, bg, render(t) }
   render(t) is called for each frame with t in ms; it must set the DOM purely from t.
   Helpers below are pure functions of t where possible. */
(function(){
  const H = {};
  // easing
  H.ease = {
    linear:x=>x,
    out:x=>1-Math.pow(1-x,3),
    in:x=>x*x*x,
    inOut:x=>x<.5?4*x*x*x:1-Math.pow(-2*x+2,3)/2,
    back:x=>{const c1=1.70158,c3=c1+1;return 1+c3*Math.pow(x-1,3)+c1*Math.pow(x-1,2)},
    spring:x=>{ if(x<=0)return 0; if(x>=1)return 1; return 1-Math.cos(x*Math.PI*2.2)*Math.exp(-x*6)*(1-x)}
  };
  H.clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v));
  H.lerp=(a,b,p)=>a+(b-a)*p;
  // progress of a segment [start, start+dur] -> 0..1 eased
  H.prog=(t,start,dur,e='out')=>{const p=H.clamp((t-start)/dur);return (H.ease[e]||H.ease.out)(p)};
  // 1 while inside window, 0 outside, with fades
  H.window=(t,start,end,fadeIn=200,fadeOut=200)=>{
    if(t<start||t>end)return 0;
    const a=H.clamp((t-start)/fadeIn), b=H.clamp((end-t)/fadeOut);
    return Math.min(a,b);
  };
  // typing: returns substring given start time and chars/sec, with slight jitter for realism
  H.typed=(t,text,start,cps=22)=>{
    if(t<start)return '';
    let n=0,acc=start;
    for(let i=0;i<text.length;i++){
      const ch=text[i];
      let d=1000/cps;
      if(ch===' ')d*=1.4; if(ch==='.'||ch===',')d*=2.2;
      d*= (0.75+ ((i*7919)%100)/200); // deterministic jitter .75-1.25
      acc+=d; if(t>=acc)n=i+1; else break;
    }
    return text.slice(0,n);
  };
  H.caret=(t,on=true)=>on&&(Math.floor(t/500)%2===0);

  // ---- DOM scaffolding ----
  function el(tag,cls,html){const e=document.createElement(tag);if(cls)e.className=cls;if(html!=null)e.innerHTML=html;return e}
  H.el=el;

  // ---- cursor ----
  const cursorSVG=`<svg width="22" height="30" viewBox="0 0 22 30" xmlns="http://www.w3.org/2000/svg"><path d="M2 2 L2 23 L7.5 18.5 L11 27 L15 25.3 L11.6 17 L19 17 Z" fill="#fff" stroke="#000" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  // path: array of {t, x, y} waypoints; clicks: array of times
  H.cursor=(t,path,clicks=[])=>{
    const c=document.getElementById('cursor'); if(!c)return;
    if(!path||!path.length){c.style.opacity=0;return}
    c.style.opacity=1;
    let x=path[0].x,y=path[0].y;
    for(let i=0;i<path.length-1;i++){
      const a=path[i],b=path[i+1];
      if(t>=b.t){x=b.x;y=b.y;continue}
      if(t>=a.t){const p=H.ease.inOut(H.clamp((t-a.t)/(b.t-a.t)));x=H.lerp(a.x,b.x,p);y=H.lerp(a.y,b.y,p);break}
    }
    c.style.left=x+'px';c.style.top=y+'px';
    const ring=c.querySelector('.ring');let rp=0;
    for(const ct of clicks){ if(t>=ct&&t<ct+420){rp=(t-ct)/420} }
    ring.style.opacity=rp?String(1-rp):'0'; ring.style.transform=`scale(${.4+rp*1.1})`;
    c.style.transform= clicks.some(ct=>t>=ct&&t<ct+120)?'translate(-3px,-2px) scale(.88)':'translate(-3px,-2px) scale(1)';
  };

  // ---- caption / title card ----
  // caps: [{from,to,text}]
  H.caption=(t,caps)=>{
    const c=document.getElementById('caption'); let shown=null;
    for(const k of caps){ if(t>=k.from&&t<=k.to){shown=k;break} }
    if(!shown){c.style.opacity=0;return}
    c.textContent=shown.text; const o=H.window(t,shown.from,shown.to,180,180); c.style.opacity=o; c.style.transform=`translateX(-50%) translateY(${(1-o)*8}px)`;
  };
  H.titleCard=(t,{from,to,kicker,title,sub,note})=>{
    const c=document.getElementById('card'); const o=H.window(t,from,to,250,350);
    c.style.opacity=o; if(o>0){c.querySelector('.k').textContent=kicker||'';c.querySelector('.t').textContent=title||'';c.querySelector('.s').textContent=sub||'';c.querySelector('.n').textContent=note||''}
  };

  // ---- backgrounds ----
  H.backgrounds={
    figma(){
      const b=el('div','bg-figma');
      b.innerHTML=`<div class="canvas">
        <div class="frame" style="left:380px;top:150px;width:360px;height:640px;border-radius:30px;background:#fff">
          <div class="lbl">iPhone 15 — Onboarding</div>
          <div style="padding:70px 28px 0 28px">
            <div style="width:64px;height:64px;border-radius:18px;background:#6366f1"></div>
            <div class="txt" style="width:70%;height:22px;margin-top:28px;background:#222;border-radius:6px"></div>
            <div class="txt" style="width:90%"></div><div class="txt" style="width:80%"></div><div class="txt" style="width:60%"></div>
            <div style="position:absolute;left:28px;right:28px;bottom:40px" class="btnmock">Continue</div>
          </div>
        </div>
        <div class="frame" style="left:790px;top:150px;width:360px;height:640px;border-radius:30px;background:#0f0f14">
          <div class="lbl">iPhone 15 — Home</div>
          <div style="padding:60px 24px 0 24px">
            <div class="txt" style="width:50%;height:18px;background:#fff;border-radius:6px;margin-top:0"></div>
            ${Array.from({length:5}).map((_,i)=>`<div style="height:84px;border-radius:16px;background:#1b1b24;margin-top:14px;display:flex;align-items:center;padding:0 16px;gap:12px"><div style="width:44px;height:44px;border-radius:12px;background:${['#6366f1','#f59e0b','#10b981','#f43f5e','#0ea5e9'][i]}"></div><div style="flex:1"><div class="txt" style="width:60%;background:#2d2d3a;margin-top:0"></div><div class="txt" style="width:40%;background:#2d2d3a"></div></div></div>`).join('')}
          </div>
        </div>
      </div>
      <div class="tb"><i class="on"></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><span style="flex:1"></span><i style="width:60px;background:#0d99ff;border-radius:8px"></i></div>
      <div class="panel l"><div class="h">Pages</div><div class="row">Onboarding</div><div class="row" style="color:#fff;background:#3a3a3a;border-radius:6px">Home</div><div class="row">Settings</div><div class="h" style="margin-top:18px">Layers</div>${Array.from({length:11}).map((_,i)=>`<div class="row"><b></b>${['Frame','Header','Card','Card','Card','Avatar','Title','Subtitle','CTA','Tab bar','Status'][i]}</div>`).join('')}</div>
      <div class="panel r"><div class="h">Design</div><div class="sw"></div><div class="sw"></div><div class="h" style="margin-top:16px">Fill</div><div class="sw" style="background:#6366f1"></div><div class="h" style="margin-top:16px">Effects</div><div class="sw"></div><div class="h" style="margin-top:16px">Export</div><div class="sw"></div></div>`;
      return b;
    },
    docs(){
      const b=el('div','bg-docs');
      b.innerHTML=`<div class="side"><div class="it">🏠 Home</div><div class="it">🔍 Search</div><div class="it" style="margin-top:14px;color:#999;font-size:11px">WORKSPACE</div><div class="it">Roadmap</div><div class="it on">Q4 Launch Plan</div><div class="it">Retro notes</div><div class="it">Hiring</div><div class="it">Design system</div></div>
      <div class="page"><div class="doc"><h1>Q4 Launch Plan</h1>
      <p>We ship the new onboarding on Nov 12. The goal is a 20% lift in day-1 retention without hurting activation on the free tier.</p>
      <h2>Scope</h2><li>Rewrite the first-run flow around a single “aha” moment</li><li>Kill the 6-step survey, replace with progressive profiling</li><li>Ship the referral loop behind a flag</li>
      <h2>Risks</h2><p>The billing migration lands the same week. If it slips, we decouple the referral loop and ship onboarding alone.</p>
      <p id="docs-typing">Open questions for Thursday<span class="caret"></span></p></div></div>`;
      return b;
    },
    browser(){
      const b=el('div','bg-browser');
      b.innerHTML=`<div class="chrome"><div class="url">🔒 stripe.com/blog/designing-for-focus</div></div>
      <div class="content"><div class="art"><h1>Designing for focus: why interruptions should earn their place</h1><div class="meta">Engineering · 9 min read</div>
      <div class="img"></div>
      <p>Every interruption makes a claim on your attention. Most products treat that claim as free. It is not. The best tools interrupt rarely, say exactly what they need, and get out of the way.</p>
      <p>We rebuilt our internal alerting around a simple rule: if a notification cannot be acted on from the notification itself, it does not ship.</p>
      <p>That rule changed how we think about context. A good interrupt arrives with the decision already framed, so the human spends their attention on judgment rather than on navigation.</p></div></div>`;
      return b;
    },
    video(){
      const b=el('div','bg-video');
      b.innerHTML=`<div class="scene"></div><div class="ttl">WWDC25 — Platforms State of the Union</div><div class="bar"><i></i></div>`;
      return b;
    }
  };

  // ---- bootstrap ----
  window.addEventListener('DOMContentLoaded',()=>{
    const D=window.DRAFT; if(!D){console.error('no DRAFT');return}
    const stage=el('div');stage.id='stage';
    const bg=el('div');bg.id='bg'; bg.appendChild(H.backgrounds[D.bg||'docs']());
    const ov=el('div');ov.id='overlay'; ov.innerHTML=D.markup||'';
    const cur=el('div');cur.id='cursor';cur.innerHTML=cursorSVG+'<div class="ring"></div>';
    const cap=el('div');cap.id='caption';
    const card=el('div');card.id='card';card.innerHTML='<div class="k"></div><div class="t"></div><div class="s"></div><div class="n"></div>';
    stage.append(bg,ov,cur,cap,card); document.body.appendChild(stage);
    if(D.setup)D.setup(H);
    window.__duration=D.duration;
    window.__seek=(t)=>{ D.render(t,H); };
    window.__seek(0);
    // live preview mode when opened in a normal browser
    if(location.hash==='#play'){const t0=performance.now();(function loop(){const t=(performance.now()-t0)%D.duration;window.__seek(t);requestAnimationFrame(loop)})()}
  });
  window.H=H;
})();
