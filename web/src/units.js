export function distanceUnit(choice){return choice==='mi'?'mi':'km'}
export function formatDistance(meters,choice){return((Number(meters)||0)/(choice==='mi'?1609.344:1000)).toFixed(2)}
