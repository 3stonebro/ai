import json, hashlib, zipfile, random
from pathlib import Path

OUT=Path(__file__).parent
assets={}
def costume(name,svg,cx,cy):
    raw=svg.encode(); h=hashlib.md5(raw).hexdigest(); assets[h+'.svg']=raw
    return dict(name=name,assetId=h,md5ext=h+'.svg',dataFormat='svg',rotationCenterX=cx,rotationCenterY=cy)
def svg(w,h,body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
class Code:
    def __init__(self): self.b={}; self.n=0
    def block(self,op,inputs=None,fields=None):
        self.n+=1; k='b'+str(self.n); self.b[k]=dict(opcode=op,next=None,parent=None,inputs=inputs or {},fields=fields or {},shadow=False,topLevel=False); return k
    def inp(self,v):
        if isinstance(v,str) and v in self.b: return [2,v]
        return [1,[4,str(v)]]
    def make(self,op,**kw): return self.block(op,{k:self.inp(v) for k,v in kw.items()})
    def chain(self,*ids):
        for a,b in zip(ids,ids[1:]): self.b[a]['next']=b; self.b[b]['parent']=a
        return ids[0]
    def script(self,*ids):
        h=self.chain(*ids); self.b[h].update(topLevel=True,x=30,y=40+sum(x['topLevel'] for x in self.b.values())*220); return h
    def sub(self,op,body,**kw):
        k=self.make(op,**kw); self.b[k]['inputs']['SUBSTACK']=[2,body]; self.b[body]['parent']=k; return k
    def var(self,n): return self.block('data_variable',fields={'VARIABLE':[n,n]})
    def set(self,n,v): return self.block('data_setvariableto',{'VALUE':self.inp(v)},{'VARIABLE':[n,n]})
    def change(self,n,v): return self.block('data_changevariableby',{'VALUE':self.inp(v)},{'VARIABLE':[n,n]})
    def key(self,k):
        m=self.block('sensing_keyoptions',fields={'KEY_OPTION':[k,None]}); self.b[m]['shadow']=True
        return self.make('sensing_keypressed',KEY_OPTION=m)
    def touch(self,n):
        m=self.block('sensing_touchingobjectmenu',fields={'TOUCHINGOBJECTMENU':[n,None]}); self.b[m]['shadow']=True
        return self.make('sensing_touchingobject',TOUCHINGOBJECTMENU=m)
    def clone(self):
        m=self.block('control_create_clone_of_menu',fields={'CLONE_OPTION':['_myself_',None]}); self.b[m]['shadow']=True
        return self.make('control_create_clone_of',CLONE_OPTION=m)
def target(name,costumes,code,stage=False):
    d=dict(isStage=stage,name=name,variables={},lists={},broadcasts={},blocks=code.b,comments={},currentCostume=0,costumes=costumes,sounds=[],volume=100,layerOrder=0)
    if stage: d.update(tempo=60,videoTransparency=50,videoState='on',textToSpeechLanguage=None)
    else: d.update(visible=True,x=0,y=0,size=100,direction=90,draggable=False,rotationStyle="don't rotate")
    return d
random.seed(7)
stars=''.join(f'<circle cx="{random.randrange(480)}" cy="{random.randrange(360)}" r="{random.choice([.7,1,1.5])}" fill="#b9d9ff" opacity=".6"/>' for _ in range(70))
bg=costume('Star arena',svg(480,360,'<rect width="480" height="360" fill="#080f27"/>'+stars+'<path d="M0 310H480" stroke="#23355c"/><text x="240" y="50" text-anchor="middle" fill="#5df0ff" font-family="sans-serif" font-weight="bold" font-size="24">NEON STAR DEFENDER</text><text x="240" y="338" text-anchor="middle" fill="#b9c9ec" font-family="sans-serif" font-size="12">ARROWS: MOVE   •   SPACE: FIRE   •   GREEN FLAG: RESTART</text>'),240,180)
c=Code(); c.script(c.block('event_whenflagclicked'),c.set('Score',0),c.set('Health',5),c.set('Wave',1),c.sub('control_forever',c.chain(c.set('Wave',c.make('operator_add',NUM1=1,NUM2=c.make('operator_mathop',NUM=c.make('operator_divide',NUM1=c.var('Score'),NUM2=10)))),c.sub('control_if',c.block('control_stop',fields={'STOP_OPTION':['all',None]}),CONDITION=c.make('operator_lt',OPERAND1=c.var('Health'),OPERAND2=1)))))
# Wave is derived from score, rounded down.
for b in c.b.values():
    if b['opcode']=='operator_mathop': b['fields']={'OPERATOR':['floor',None]}
stage=target('Stage',[bg],c,True); stage['variables']={n:[n,v] for n,v in [('Score',0),('Health',5),('Wave',1)]}
ship=costume('Neon fighter',svg(44,52,'<path d="M22 2L40 42L28 37L22 48L16 37L4 42Z" fill="#25d8ee" stroke="#d0fcff" stroke-width="2"/><path d="M22 12L28 31H16Z" fill="#2741a0"/><path d="M17 44L22 52L27 44" fill="#ffb743"/>'),22,26)
p=Code(); moves=[]
for key,op,val in [('left arrow','motion_changexby',-6),('right arrow','motion_changexby',6),('up arrow','motion_changeyby',6),('down arrow','motion_changeyby',-6)]:
    moves.append(p.sub('control_if',p.make(op,**{('DX' if 'x' in op else 'DY'):val}),CONDITION=p.key(key)))
for reporter,limit,cmp,op,inp in [('motion_xposition',215,'operator_gt','motion_setx','X'),('motion_xposition',-215,'operator_lt','motion_setx','X'),('motion_yposition',100,'operator_gt','motion_sety','Y'),('motion_yposition',-130,'operator_lt','motion_sety','Y')]:
    moves.append(p.sub('control_if',p.make(op,**{inp:limit}),CONDITION=p.make(cmp,OPERAND1=p.block(reporter),OPERAND2=limit)))
p.script(p.block('event_whenflagclicked'),p.make('motion_gotoxy',X=0,Y=-110),p.block('looks_show'),p.sub('control_forever',p.chain(*moves)))
player=target('Player',[ship],p)
laser=costume('Plasma bolt',svg(8,22,'<rect x="1" y="1" width="6" height="20" rx="3" fill="#7fffff"/><rect x="3" y="2" width="2" height="18" fill="white"/>'),4,11)
l=Code(); l.script(l.block('event_whenflagclicked'),l.block('looks_hide'),l.sub('control_forever',l.chain(l.sub('control_if',l.chain(l.clone(),l.make('control_wait',DURATION=.17)),CONDITION=l.key('space')),l.make('control_wait',DURATION=.01))))
menu=l.block('motion_goto_menu',fields={'TO':['Player',None]}); l.b[menu]['shadow']=True
l.script(l.block('control_start_as_clone'),l.make('motion_goto',TO=menu),l.block('looks_show'),l.sub('control_repeat_until',l.chain(l.make('motion_changeyby',DY=14),l.make('control_wait',DURATION=.02)),CONDITION=l.make('operator_gt',OPERAND1=l.block('motion_yposition'),OPERAND2=175)),l.block('control_delete_this_clone'))
bullet=target('Laser',[laser],l)
enemycost=costume('Drone',svg(44,34,'<path d="M3 12L14 4H30L41 12L35 29H9Z" fill="#f15b91" stroke="#ffb8dc" stroke-width="2"/><path d="M12 14H32V22H12Z" fill="#401950"/><circle cx="17" cy="18" r="2" fill="#ffdd7e"/><circle cx="27" cy="18" r="2" fill="#ffdd7e"/>'),22,17)
e=Code(); e.script(e.block('event_whenflagclicked'),e.block('looks_hide'),e.sub('control_forever',e.chain(e.clone(),e.make('control_wait',DURATION=e.make('operator_divide',NUM1=.8,NUM2=e.make('operator_add',NUM1=1,NUM2=e.make('operator_multiply',NUM1=e.var('Wave'),NUM2=.12)))))))
hit=e.chain(e.change('Score',1),e.block('control_delete_this_clone'))
damage=e.chain(e.change('Health',-1),e.block('control_delete_this_clone'))
step=e.chain(e.make('motion_changeyby',DY=e.make('operator_subtract',NUM1=-2,NUM2=e.make('operator_multiply',NUM1=e.var('Wave'),NUM2=.35))),e.sub('control_if',hit,CONDITION=e.touch('Laser')),e.sub('control_if',damage,CONDITION=e.make('operator_or',OPERAND1=e.touch('Player'),OPERAND2=e.make('operator_lt',OPERAND1=e.block('motion_yposition'),OPERAND2=-145))),e.make('control_wait',DURATION=.03))
e.script(e.block('control_start_as_clone'),e.make('motion_gotoxy',X=e.make('operator_random',FROM=-210,TO=210),Y=150),e.block('looks_show'),e.sub('control_forever',step))
enemy=target('Enemy',[enemycost],e)
overcost=costume('Game over',svg(360,110,'<rect x="2" y="2" width="356" height="106" rx="18" fill="#152344" stroke="#ff699e" stroke-width="3"/><text x="180" y="48" text-anchor="middle" font-family="sans-serif" font-size="32" font-weight="bold" fill="#ff8db7">GAME OVER</text><text x="180" y="80" text-anchor="middle" font-family="sans-serif" font-size="16" fill="white">Click the green flag to fight again!</text>'),180,55)
o=Code(); o.script(o.block('event_whenflagclicked'),o.block('looks_hide'),o.make('control_wait_until',CONDITION=o.make('operator_lt',OPERAND1=o.var('Health'),OPERAND2=1)),o.block('looks_show'))
# Stop after the overlay has time to become visible.
for k,b in list(c.b.items()):
    if b['opcode']=='control_stop':
        wait=c.make('control_wait',DURATION=.15)
        parent=b['parent']; c.b[parent]['inputs']['SUBSTACK']=[2,wait]; c.b[wait]['parent']=parent; c.chain(wait,k)
over=target('Game Over',[overcost],o); over['layerOrder']=10
monitors=[dict(id=n,mode='default',opcode='data_variable',params={'VARIABLE':n},spriteName=None,value=v,width=0,height=0,x=x,y=8,visible=True,sliderMin=0,sliderMax=100,isDiscrete=True) for n,v,x in [('Score',0,8),('Health',5,165),('Wave',1,325)]]
project=dict(targets=[stage,player,bullet,enemy,over],monitors=monitors,extensions=[],meta={'semver':'3.0.0','vm':'0.2.0','agent':'Codex'})
for layer,t in enumerate(project['targets']):
    t['layerOrder']=layer
for t in project['targets']:
    for k,b in t['blocks'].items():
        for value in b['inputs'].values():
            if isinstance(value[1],str): t['blocks'][value[1]]['parent']=k
for t in [bullet,enemy,over]: t['visible']=False
with zipfile.ZipFile(OUT/'Neon Star Defender.sb3','w',zipfile.ZIP_DEFLATED) as z:
    z.writestr('project.json',json.dumps(project))
    for name,data in assets.items(): z.writestr(name,data)
print(OUT/'Neon Star Defender.sb3')
