from pathlib import Path
import json,html
p=Path(__file__).resolve().parent;d=json.loads((p/'figure-data.json').read_text())
for mobile in [False,True]:
 w,h=(480,780) if mobile else(1000,660);x0=40 if mobile else 80;scale=3.6 if mobile else 7;out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="t desc"><title id="t">One minute, two deadlines</title><desc id="desc">Recorded software control with simulated system effects. Ready holds an initial sixty-second arming deadline. A simulated lid event forty-seven seconds later schedules a new full minute. Expiry was not observed after the Mac locked.</desc><rect width="100%" height="100%" fill="#fffaf3"/><g font-family="Arial, sans-serif" fill="#252b25">']
 def text(x,y,t,size=22,color=None):out.append(f'<text x="{x}" y="{y}" font-size="{size}"'+(f' fill="{color}"' if color else'')+'>'+html.escape(t)+'</text>')
 text(x0,42,'WideAwake / native control case',18,'#98500c')
 for i,t in enumerate(['One minute,','two deadlines.'] if mobile else['One minute, two deadlines.']):text(x0,98+i*46,t,40)
 text(x0,220 if mobile else 150,'All system effects simulated.',22)
 y1,y2=(330,470) if mobile else(250,390)
 for y,start,end,phase in [(y1,0,d['ready_deadline_seconds'],'Ready'),(y2,d['close_seconds_from_selected_deadline'],d['running_deadline_seconds'],'Running')]:
  text(x0,y-45,phase,26);out.append(f'<path data-start="{start}" data-end="{end}" data-scale="{scale}" data-x0="{x0}" d="M{x0+start*scale},{y} H{x0+end*scale}" stroke="#b66316" stroke-width="8"/><circle cx="{x0+start*scale}" cy="{y}" r="7" fill="#b66316"/><circle cx="{x0+end*scale}" cy="{y}" r="7" fill="#fffaf3" stroke="#b66316" stroke-width="3"/>')
  text(x0+start*scale,y+34,f'{int(start)} s',20);text(x0+end*scale-28,y+34,f'{int(end)} s',20)
 fy=580 if mobile else 500
 for i,t in enumerate(['Selected duration: 60 seconds.','Stored deadline shifts by 47 seconds.','The lid event schedules a full minute.']):text(x0,fy+i*34,t,20 if mobile else 24)
 for i,t in enumerate(['Scheduled deadlines only.','Expiry, cancel and reopen await unlocked UI.']):text(x0,h-62+i*27,t,16 if mobile else 19,'#5c625b')
 out.append('</g></svg>');name='deadline-mobile' if mobile else'deadline';svg=''.join(out);(p/(name+'.svg')).write_text(svg);(p/(name+'.html')).write_text('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0}svg{display:block;width:100%;height:auto}</style>'+svg)
