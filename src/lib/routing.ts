export const BASE={latitude:-3.304994801080341,longitude:-39.2765194153434};
type Point={latitude:number;longitude:number};
const distance=(a:Point,b:Point)=>{const R=6371,dLat=(b.latitude-a.latitude)*Math.PI/180,dLon=(b.longitude-a.longitude)*Math.PI/180;const v=Math.sin(dLat/2)**2+Math.cos(a.latitude*Math.PI/180)*Math.cos(b.latitude*Math.PI/180)*Math.sin(dLon/2)**2;return 2*R*Math.atan2(Math.sqrt(v),Math.sqrt(1-v))};
const total=(items:Point[])=>{let d=0,p=BASE;for(const x of items){d+=distance(p,x);p=x}return d+distance(p,BASE)};
export function optimizeRoute<T extends Point>(input:T[]){let pending=[...input].slice(0,10),current:Point=BASE,route:T[]=[];while(pending.length){pending.sort((a,b)=>distance(current,a)-distance(current,b));const next=pending.shift()!;route.push(next);current=next}let improved=true;while(improved){improved=false;for(let i=0;i<route.length-1;i++)for(let j=i+1;j<route.length;j++){const candidate=[...route.slice(0,i),...route.slice(i,j+1).reverse(),...route.slice(j+1)];if(total(candidate)+.01<total(route)){route=candidate;improved=true}}}return{stops:route,distanceKm:Number(total(route).toFixed(1))}}

export async function optimizeRoadRoute<T extends Point>(input:T[]){
  const points=input.slice(0,10);
  if(!points.length)return{stops:[] as T[],distanceKm:0,roadDistance:false};
  try{
    const all=[BASE,...points];
    const coordinates=all.map(p=>`${p.longitude},${p.latitude}`).join(';');
    const response=await fetch(`https://router.project-osrm.org/table/v1/driving/${coordinates}?annotations=distance`);
    if(!response.ok)throw new Error('Serviço de rotas indisponível');
    const json=await response.json() as {code:string;distances:(number|null)[][]};
    if(json.code!=='Ok'||!json.distances)throw new Error('Matriz rodoviária inválida');
    const matrix=json.distances;
    const pending=points.map((point,index)=>({point,index:index+1}));
    const ordered:{point:T;index:number}[]=[];
    let current=0;
    while(pending.length){
      pending.sort((a,b)=>(matrix[current][a.index]??Infinity)-(matrix[current][b.index]??Infinity));
      const next=pending.shift()!;ordered.push(next);current=next.index;
    }
    const routeDistance=(route:typeof ordered)=>{
      let meters=0,from=0;
      for(const stop of route){const leg=matrix[from][stop.index];if(leg==null)return Infinity;meters+=leg;from=stop.index}
      const back=matrix[from][0];return back==null?Infinity:meters+back;
    };
    let improved=true;
    while(improved){
      improved=false;
      for(let i=0;i<ordered.length-1;i++)for(let j=i+1;j<ordered.length;j++){
        const candidate=[...ordered.slice(0,i),...ordered.slice(i,j+1).reverse(),...ordered.slice(j+1)];
        if(routeDistance(candidate)+10<routeDistance(ordered)){ordered.splice(0,ordered.length,...candidate);improved=true}
      }
    }
    return{stops:ordered.map(x=>x.point),distanceKm:Number((routeDistance(ordered)/1000).toFixed(1)),roadDistance:true};
  }catch{
    const fallback=optimizeRoute(points);
    return{...fallback,roadDistance:false};
  }
}
