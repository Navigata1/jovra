#!/usr/bin/env python3
"""Generate ordinary named Codable contract models. Run only in a contract-fix PR after schema changes.

This is a build-time maintenance tool, never a client JSON interpreter. The shipped Swift models
have typed stored properties, enums for schema choices, and discriminator-based union decoders.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / 'spec/schemas'
DEST = ROOT / 'ios/Packages/JovraCore/Sources/JovraCore/Contracts'
SPECS = {
    'session': ('SessionDocument', 'Session'),
    'equipment': ('EquipmentDocument', 'Equipment'),
    'practice-plan': ('PracticePlanDocument', 'Practice'),
    'archive-manifest': ('ArchiveManifest', 'Archive'),
    'export': ('ExportManifest', 'Export'),
    'capability-registry': ('CapabilityRegistry', 'Capability'),
    'sample-media-manifest': ('SampleMediaManifest', 'SampleMedia'),
    'ground-truth': ('GroundTruthRecord', 'GroundTruth'),
    'benchmark-record': ('BenchmarkRecord', 'Benchmark'),
    'benchmark-bindings': ('BenchmarkBindings', 'BenchmarkBinding'),
    'csv-contract': ('CSVContract', 'CSV'),
}
COMMON_NAMES = {'schemaVersion':'SchemaVersion','provenanceStatus':'Provenance',
 'mediaTime':'MediaTime','frameRate':'RecordedFrameRate','fileRef':'RecordFileReference',
 'point2':'CourtPoint2D','provenance':'RecordProvenance','ratio':'RateRatio', 'side':'Side',
 'timeRange':'MediaRange','sideCounts':'SideCounts','appInfo':'AppInfo'}
KEYWORDS = set('default repeat in case let var func class struct enum protocol extension import self Self Type associatedtype static switch where throws throw try return init deinit subscript defer as is operator public private internal fileprivate open actor await'.split())

def pascal(s):
    return ''.join(x[:1].upper()+x[1:] for x in re.split('[^A-Za-z0-9]+',s) if x)

def identifier(s):
    result = re.sub('[^A-Za-z0-9_]', '_', s)
    if result[:1].isdigit(): result = 'value' + result
    return '`'+result+'`' if result in KEYWORDS else result

def case_name(value, single=False):
    if single: return 'value'
    if value == '>=': return 'atLeast'
    if value == '<=': return 'atMost'
    s=pascal(str(value));s=s[:1].lower()+s[1:]
    return identifier(s)

class Generator:
    def __init__(self):
        self.docs={p.stem.removesuffix('.schema'):json.loads(p.read_text()) for p in SCHEMAS.glob('*.schema.json')}
        self.names={};self.output={};self.current=[]
        for file,(root,prefix) in SPECS.items():
            self.names[(file,'')]=root
            for key in self.docs[file].get('$defs',{}): self.names[(file,'/$defs/'+key)]=prefix+pascal(key)
        for key,name in COMMON_NAMES.items():self.names[('common','/$defs/'+key)]=name
    def node(self,file,path):
        d=self.docs[file]
        for part in path.strip('/').split('/') if path else []:d=d[part]
        return d
    def ref(self,ref,file):
        path,_,fragment=ref.partition('#')
        target=Path(path).name.removesuffix('.schema.json') if path else file
        return target,fragment
    def flatten(self,s,file):
        if not isinstance(s,dict):return s
        result={k:v for k,v in s.items() if k!='allOf'}
        for part in s.get('allOf',[]):
            if '$ref' not in part:continue
            tf,tp=self.ref(part['$ref'],file);base=self.flatten(self.node(tf,tp),tf)
            if tf != file:
                base = json.loads(json.dumps(base))
                def qualify(node):
                    if isinstance(node, dict):
                        if isinstance(node.get('$ref'), str) and node['$ref'].startswith('#'):
                            node['$ref'] = tf + '.schema.json' + node['$ref']
                        for child in node.values(): qualify(child)
                    elif isinstance(node, list):
                        for child in node: qualify(child)
                qualify(base)
            props=dict(base.get('properties',{}))
            props.update({k:v for k,v in result.get('properties',{}).items() if v is not True})
            result['properties']=props
            result['required']=list(dict.fromkeys(base.get('required',[])+result.get('required',[])))
            result.setdefault('type',base.get('type'))
        return result
    def type(self,s,file,path,hint):
        if '$ref' in s:
            tf,tp=self.ref(s['$ref'],file)
            if (tf,tp)==('common','/$defs/schemaVersion'):return 'SchemaVersion'
            if (tf,tp)==('common','/$defs/mediaTime'):return 'MediaTime'
            if (tf,tp)==('common','/$defs/provenanceStatus'):return 'Provenance'
            return self.type(self.node(tf,tp),tf,tp,self.names.get((tf,tp),hint))
        if isinstance(s.get('type'),list):
            types=s['type']
            if 'null'in types:
                child=dict(s);child['type']=next(t for t in types if t!='null')
                return 'ContractNullable<'+self.type(child,file,path+'/nonnull',hint)+'>'
            return 'ScalarValue'
        union=s.get('oneOf')
        if union:
            nonnull=[u for u in union if u.get('type')!='null']
            if len(nonnull)==1 and len(nonnull)<len(union):
                return 'ContractNullable<'+self.type(nonnull[0],file,path+'/oneOf/value',hint)+'>'
            name=self.names.get((file,path),hint)
            if name not in self.output:
                self.output[name]='';self.emit_union(name,union,file,path)
            return name
        if 'const'in s and isinstance(s['const'],bool):return 'Bool'
        if 'enum' in s and None in s['enum']:
            child = dict(s); child['enum'] = [v for v in s['enum'] if v is not None]
            return 'ContractNullable<' + self.type(child, file, path+'/nonnull', hint) + '>'
        enum=s.get('enum',[s['const']] if 'const'in s else None)
        if enum is not None:
            name=self.names.get((file,path),hint)
            if name not in self.output:
                rawtype = 'Int' if all(isinstance(v, int) and not isinstance(v, bool) for v in enum) else 'String'
                self.output[name]='public enum '+name+': '+rawtype+', Codable, CaseIterable, Hashable, Sendable {\n'+''.join('    case '+case_name(v,len(enum)==1)+' = '+json.dumps(v,ensure_ascii=False)+'\n' for v in enum)+'}\n'
            return name
        primitive={'string':'String','integer':'Int','number':'Decimal','boolean':'Bool'}
        if s.get('type')in primitive:return primitive[s['type']]
        if s.get('type')=='array':
            if 'items' not in s and 'prefixItems' in s and all(isinstance(v.get('const'), str) for v in s['prefixItems']):
                return '[String]'
            if 'items' not in s and file == 'benchmark-record' and path.endswith('/outputs'):
                return '[BenchmarkOutputValue]'
            return '['+self.type(s['items'],file,path+'/items',hint+'Item')+']'
        s=self.flatten(s,file)
        if s.get('type')=='object' or 'properties'in s:
            if isinstance(s.get('additionalProperties'),dict):return '[String: '+self.type(s['additionalProperties'],file,path+'/additionalProperties',hint+'Value')+']'
            name=self.names.get((file,path),hint)
            if name not in self.output:
                self.output[name]='';self.emit_object(name,s,file,path)
            return name
        raise ValueError((file,path,s))
    def emit_object(self,name,s,file,path):
        fields=[]
        for key,v in s.get('properties',{}).items():
            if v is False:continue
            if v is True:raise ValueError('unresolved inherited property '+key)
            t=self.type(v,file,path+'/properties/'+key,name+pascal(key))
            required=key in s.get('required',[])
            default=None
            if not required:t+='?';default='nil'
            elif key=='schemaVersion':default='.v1_1' if file in ['session','practice-plan','archive-manifest','export'] else '.v1'
            elif 'const'in v:
                default=str(v['const']).lower() if isinstance(v['const'],bool) else '.value'
            fields.append((key,t,required,default))
        lines=['public struct '+name+': Codable, Equatable, Sendable {']
        lines+=['    public var '+identifier(k)+': '+t for k,t,_,_ in fields]
        lines+=['','    public init('+', '.join(identifier(k)+': '+t+(' = '+default if default else '') for k,t,_,default in fields)+') {']
        lines+=['        self.'+identifier(k)+' = '+identifier(k) for k,t,_,_ in fields]
        lines+=['    }','}']
        self.output[name]='\n'.join(lines)+'\n'
    def emit_union(self,name,union,file,path):
        members=[];discriminator=None
        for i,u in enumerate(union):
            tf,tp=self.ref(u['$ref'],file) if '$ref'in u else (file,path+'/oneOf/'+str(i))
            body=self.node(tf,tp) if '$ref'in u else u
            for field in ['type','kind']:
                prop=body.get('properties',{}).get(field,{})
                if 'const'in prop or 'enum'in prop:
                    discriminator=discriminator or field
                    values=prop.get('enum',[prop.get('const')]);break
            else:raise ValueError('union has no discriminator '+name)
            typename=self.type(u,file,path+'/oneOf/'+str(i),name+pascal(values[0]))
            members.append((case_name(values[0]),typename,values))
        lines=['public enum '+name+': Codable, Equatable, Sendable {']
        lines+=['    case '+c+'('+t+')' for c,t,_ in members]
        lines+=['','    private enum CodingKeys: String, CodingKey { case '+identifier(discriminator)+' }',
                '    public init(from decoder: Decoder) throws {',
                '        let container = try decoder.container(keyedBy: CodingKeys.self)',
                '        let tag = try container.decode(String.self, forKey: .'+identifier(discriminator)+')',
                '        switch tag {']
        for c,t,vs in members:lines+=['        case '+', '.join(json.dumps(v) for v in vs)+': self = .'+c+'(try '+t+'(from: decoder))']
        lines+=['        default: throw DecodingError.dataCorruptedError(forKey: .'+identifier(discriminator)+', in: container, debugDescription: "Unknown '+name+' discriminator")',
                '        }','    }','    public func encode(to encoder: Encoder) throws {','        switch self {']
        lines+=['        case .'+c+'(let value): try value.encode(to: encoder)' for c,t,vs in members]
        lines+=['        }','    }']
        if name=='SessionLogEvent':
            for prop,typ in [('id','String'),('seq','Int')]:
                lines+=['    public var '+prop+': '+typ+' {','        switch self {']
                lines+=['        case .'+c+'(let value): value.'+prop for c,t,vs in members]
                lines+=['        }','    }']
            lines+=['    public var typeString: String {','        switch self {']
            lines+=['        case .'+c+'(let value): value.type.rawValue' for c,t,vs in members]
            lines+=['        }','    }']
        lines+=['}'];self.output[name]='\n'.join(lines)+'\n'
    def run(self,files):
        self.type(self.docs['common']['$defs']['provenance'],'common','/$defs/provenance','RecordProvenance')
        for file in files:self.type(self.docs[file],file,'',SPECS[file][0])
        DEST.mkdir(parents=True,exist_ok=True)
        header='// Generated named models from spec/schemas by scripts/spec/generate_swift_models.py.\n// Contract changes require a contract-fix PR; no runtime JSON dictionaries are used.\nimport Foundation\n\n'
        (DEST/'DocumentModels.swift').write_text(header+'\n'.join(self.output[k] for k in sorted(self.output)))
        print('Generated',len(self.output),'typed models/enums for',','.join(files))

if __name__=='__main__':Generator().run(sys.argv[1:] or list(SPECS))
