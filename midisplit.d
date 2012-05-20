import std.stdio;
import std.exception;
import std.array;
import std.range;
import std.algorithm;
import std.file;
import std.conv;
import std.getopt;
import std.path;

immutable ubyte ub0x80 = 0x80;
//MThd == MIDI track header magic no, 0006 == remaining length of header
//bytes 8,9: MIDI format  10,11 num racks 12,13 division (timing) 
ubyte[14] midiHeader = ['M','T','h','d',0,0,0,6,0,0,0,0,0,0];

  class MidiTrack {
  private:
    ubyte[8] _header = ['M','T','r','k',0,0,0,0];
    MidiEvent[] _events;
  public:
    //void addEvents(R)(R m)if((is(typeof(front(R)) == MidiEvent)) || (is(typeof(R.front) == MidiEvent))){_events~=m;}
    void addEvents(MidiEvent[] m) {_events~=m;}
    void addEvents(MidiEvent m) {_events~=m;}
    void setTrackLength(uint l){
      for (int i = 0; i < 4; ++i){
	_header[7-i] = l>>(i*8) & 0xFF;
      }
    }
    void setTrackLength(){ setTrackLength(length); }
    @property events() { return _events; }
    @property uint length() {
      auto sum = reduce!(function uint(uint t,MidiEvent m) {return t + m.length;})(0u, _events);
      setTrackLength(sum);
      return sum + _header.sizeof;
    }
    @property ubyte[] representation(){
      ubyte[] r;
      r = reduce!(function ubyte[](ubyte[] acc,MidiEvent m){ return acc ~ m.representation;})(r, _events);
      setTrackLength(r.length);
      return _header ~ r;
    }
    unittest{
      auto m1 = MidiEvent(100,99,[1,2,3]);
      auto m2 = MidiEvent(101,45,[1,2,3,1,2,3,1,2,3]);
      auto t = new MidiTrack;
      t.addEvents([m1,m2]);
      writeln(t.representation);
      assert(t.length == 24);
      assert(t.length == t.representation.length);
    }
    auto uniqueInstruments(){
      //select only events that concern instruments
      auto events = filter!(function bool(a){return (a.type >=0x80) && (a.type <= 0xAF);})(_events);
      ubyte[uint] r;
      //remove dups
      r = reduce!(function ubyte[uint](ubyte[uint] acc, MidiEvent m)
			      { acc[m.instrument]++; return acc; })(r, events);
      return sort(r.keys);
    }
    unittest{
      auto m1 = MidiEvent(90,0x81,[61,2,3]);
      auto m2 = MidiEvent(99,0x99,[35,2,3,1,2,3,1,2,3]);
      auto t = new MidiTrack;
      t.addEvents([m1,m2]);
      version(none)t.uniqueInstruments();
    }
  }

  ///See Midi format spec
    auto midiRepToInt(ubyte[] r){
      uint t;
      t = front(r);
      if ( t & 0x80){
	t ^= 0x80;
	do {
	  popFront(r);
	  t <<= 7;
	  t |= (front(r) & 0x7F);
	} while (front(r) & 0x80);
      }else{
	popFront(r);
      }
      return t;
    }

unittest{
  assert (midiRepToInt([0x01]) == 0x01);
  assert (midiRepToInt([0x81,0x00]) == 0x80);
  assert (midiRepToInt([0xC0,0x00]) == 0x2000);
  assert (midiRepToInt([0xFF,0x7F]) == 0x3FFF);
  assert (midiRepToInt([0xFF,0xFF,0xFF,0x7F]) == 0x0FFFFFFF);
}
///See Midi format spec
auto intToMidiRep(uint t){
  ubyte[] r = [t & 0x7F] ;
  while (t >>= 7){
    r = [cast(ubyte)((0x7F & t ) | 0x80)] ~ r;
  }
  return r;
}
unittest{
  assert (intToMidiRep(0x01) == [0x01]);
  assert (intToMidiRep(0x3FFF) == [0xFF,0x7F]);
  assert (intToMidiRep(0x2000) == [0xC0,0x00]);
  assert (intToMidiRep(0x80) == [0x81,0x00]);
  assert (intToMidiRep(0x0FFFFFFF) == [0xFF,0xFF,0xFF,0x7F]);
}

struct MidiEvent {
private:
  uint _deltaTime;
  ubyte _type; 
  ubyte[] _bytes;

protected:
  @property auto instrument(){ return _bytes[0]; }
  @property auto subtype(){ return _bytes[0]; }
  @property auto type(){ return _type; }
  @property auto deltaRep(){ return intToMidiRep(_deltaTime); }
  @property auto ref deltaTime(){ return _deltaTime;}
  @property auto ref deltaTime(ubyte[] dt){ _deltaTime = midiRepToInt(dt); return _deltaTime;}
  @property uint length() { return deltaRep.length + _type.sizeof + _bytes.length; }
  @property ubyte[] representation(){return deltaRep ~ [_type] ~ _bytes;}

  bool isInstrumentEvent(){ return (_type >=0x80) && (_type <= 0xAF); }

  this(uint d, ubyte t, ubyte[] b){
    _deltaTime = d;
    _type = t;
    _bytes = b;
  }
  this(ubyte[] d, ubyte t, ubyte[] b){
    this(midiRepToInt(d),t,b);
  }
  unittest{
    auto m = new MidiEvent(100,99,[1,2,3]);
    assert (m.length == m.representation.length);
    m.deltaTime = 123;
    assert(m.deltaRep == [123]);
    m.deltaTime = [32];
    assert(m.deltaTime == 32);
  }
}

  MidiEvent parseMidiEvent(ref ubyte[] bytes){
    auto tup = findSplitAfter!(function (x,y){ return (x < y); })(bytes,[ub0x80]);
    if ((tup[0].empty) || (tup[1].empty)){
      writeln();
      writeln(tup[0]);
      writeln(tup[1]);
    }
    enforce((!tup[0].empty) && (!tup[1].empty));
    auto deltaRep = tup[0];
    bytes = tup[1];
    auto type = front(bytes);
    popFront(bytes);
    ubyte[] data;
    if (type >= ub0x80 && type < 0xF0){
      data = bytes[0 .. bytesTakenByMidiType(type)];
      bytes = bytes[bytesTakenByMidiType(type) .. $];
    }else if (type == 0xFF){
      data = bytes[0 .. bytes[1]+2]; //+2 for the subtype and length bytes
      popFrontN(bytes,bytes[1]+2);
    }else if (type == 0xF0 || type == 0xF7){
      data = bytes[0 .. bytes[0]+1]; //+1 for length
      popFrontN(bytes,bytes[0]+1);
    }else{
      throw new Exception ("Unknown MIDI event type -- " ~ type);
    }
    return MidiEvent(deltaRep,type,data);				 
  }

unittest{
  ubyte[] bytes = [00,128,1,2,220,6,255,9,03,65,66,67,45,0xF0,4,3,2,1,0];
  MidiEvent m = parseMidiEvent(bytes);
  assert(m.representation == [0, 128, 1, 2]);
  m = parseMidiEvent(bytes);
  assert(m.representation == [220, 6, 255, 9, 3, 65, 66, 67]);
  m = parseMidiEvent(bytes);
  assert(m.representation == [45, 240, 4, 3, 2, 1, 0]);
}

class Options {
public:
  static {
    ubyte[][] trackInstruments; 
    string[] trackNames;
    string inFile;
    string outFile;
    bool analyzeOnly = false;
    bool useGmNames = false;
    bool instrumentPerTrack = false;
    bool sysexInAllTracks = false;

    bool validCommandline = true;

    void processOptions(ref string[] opts){
      void usage(){
	stderr.write(
		     "Usage: midisplit [OPTION]... FILE\n"
		     "  -a, --analyze\t\tdon't process, only analyze MIDI of FILE\n"
		     "  -g, --gmnames\t\tuse standard General MIDI names for tracks\n"
		     "  -n, --names  \t\tnames for tracks.  May be comma separated\n"
		     "               \t\t  or repeated for multiples\n"
		     "  -o, --outfile\t\toutput file name.  Default is to adapt FILE name.\n"
		     "  -s, --solo   \t\tuse one track per instrument in FILE\n"
		     "  -t, --track  \t\tgroups of comma separated instruments that should\n"
		     "               \t\t  be on the same track.  May be repeated\n"
		     "  -x, --sysex  \t\trepeat sysex events in all tracks\n"
		     "  -h, --help,--usage\tprint this message\n"
		     );
      }
      void addTrackNames(string opt, string val){
	trackNames ~= split!(string,string)(val,",");
      }
      void addTrackInstruments(string opt, string val){
	val = "[" ~ val ~ "]";
	trackInstruments ~= parse!(ubyte[],string)(val);
      }
      getopt(opts,
	     "outfile|o", &outFile,
	     "analyze|a", &analyzeOnly,
	     "gmnames|g", &useGmNames,
	     "solo|s", &instrumentPerTrack,
	     "sysex|x", &sysexInAllTracks,
	     "names|n", &addTrackNames,
	     "track|t", &addTrackInstruments,
	     "help|usage|h", &usage);
      useDefaults(trackInstruments.empty,trackNames.empty);
      popFront(opts);
      enforce(!opts.empty,"No FILE specified.  Run with -h for usage."); 
      inFile = front(opts);
      if (outFile.empty){outFile = stripExtension(baseName(inFile)) ~ "SPLIT" ~ extension(inFile);}
    }

    void filterTrackInstruments(R)(R insts)
      if (is(typeof(insts.front != 6) == bool)){
	foreach(ref i; trackInstruments){
	  auto filtered = filter!(delegate bool(x){return canFind(insts,x);})(sort(i));
	  i.length = 0;
	  foreach (f ;filtered){
	    i ~= f;
	  }
	} 
      }

    void useDefaults(bool instruments, bool names){
      if (instruments){
	trackInstruments = [ [35,36] , [38,40] ];
      }
      if (names){
	trackNames = ["Kick","Snare"];
      }
    }
  }
  unittest{
    version(none){
      string[] s = [ "fookle","-t1,2,3" , "-t4,5", "-nyee,hah", "myfilename.mid" ];
      processOptions(s);
      assert(trackInstruments == [ [1,2,3], [4,5] ]);
      assert(trackNames == [ "yee","hah"]);
      assert(outFile == "myfilenameSPLIT.mid");
    }
  }
}

  MidiTrack filteredCopyTrack(U)(MidiTrack inTrack, U insts)
    if (is (typeof(front(U) != 6) == bool)){
      uint preserveDelta(uint acc, MidiEvent e) {
	if (e.isInstrumentEvent && !canFind(insts,e.instrument)) {
	  return e.deltaTime;
	} else {
	  e.deltaTime += acc; 
	  return 0;
	}
      }
      MidiEvent[] inEvents = inTrack.events[0..$];

      auto remainder = reduce!(preserveDelta)(0u,inEvents);
      auto outEvents = filter!(delegate bool(e) {return ((!e.isInstrumentEvent) || canFind(insts,e.instrument));})(inEvents);

      auto t = new MidiTrack;
      foreach( e; outEvents){
	t.addEvents(e);
      }
      writefln("%u events added in filteredCopyTrack",t.events.length); 
      t.setTrackLength();
      return t;
    } 

MidiTrack parseInputFile(string inFile = Options.inFile, uint trackNum = 1){
    enforce(exists(inFile),inFile ~ " does not exist.");
    auto bytes = cast(ubyte[]) read(inFile);
    enforce(bytes.length >= 25,inFile ~ " is too small to be a MIDI file.");
    enforce(startsWith(bytes,['M','T','h','d']),inFile ~ " is not a MIDI file.");
    midiHeader[] = bytes[0..14];
    popFrontN(bytes,14);
    //TODO: use findSkip for finding a single track in a multitrack file
    enforce(startsWith(bytes,['M','T','r','k']),inFile ~ " has no track at expected point in file");
    debug {
      popFrontN(bytes,4);
      uint tsize = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[0];
      writefln ("reported track size: %d",tsize);  
      popFrontN(bytes,4);
      writefln ("bytes size:          %d",bytes.length);
      enforce(endsWith(bytes,[0xFF,0x2F,00]),"Track does not terminate correctly");
    }else{
      popFrontN(bytes,8);
    }
    auto t = new MidiTrack;
    while (!bytes.empty){
      t.addEvents([parseMidiEvent(bytes)]);
    }
    writefln("%d events added in parseInputFile",t.events.length);
    return t;
  }



int main(string[] args){
  try {
    Options.processOptions(args);
    auto inTrack = parseInputFile();
    //writeln(track.representation);
    auto uniqs = array(inTrack.uniqueInstruments);
    writeln(uniqs);
    Options.filterTrackInstruments(uniqs);
    auto nTracks = count!("!a.empty")(Options.trackInstruments);
    MidiTrack outTracks[];
    ubyte[] outBytes = midiHeader;
    outBytes[9] = 1; // MIDI format 1 (multitrack)
    outBytes[11] = cast(ubyte)nTracks;
    auto m = new MidiTrack;
    foreach ( f; Options.trackInstruments){
      if(f.empty) break;
      m = filteredCopyTrack(inTrack,f); 
      outBytes ~= m.representation;
    }
    std.file.write(Options.outFile,outBytes);

  }catch(Exception e){
    debug{
      throw e;
    }else{
      stderr.writeln(e.msg);
      return 42;
    }
  }
  return 0;
}

ubyte bytesTakenByMidiType(ubyte type){
  switch (type){
  case 0x80: .. case 0xBF: case 0xE0: .. case 0xEF:
    return 2;
  case 0xC0: .. case 0xDF:
    return 1;
  case 0xF1: .. case 0xF6: case 0xF8: .. case 0xFE:
    return 0;
  default:
    throw new Exception("No fixed Midi data length for" ~ type);
  }
}

string gmName(int inst){

  switch(inst){

  case 35:
    return "Bass Drum 2";
  case 36:
    return "Bass Drum 1";
  case 37:
    return "Side Stick/Rimshot";
  case 38:
    return "Snare Drum 1";
  case 39:
    return "Hand Clap";
  case 40:
    return "Snare Drum 2";
  case 41:
    return "Low Tom 2";
  case 42:
    return "Closed Hi-hat";
  case 43:
    return "Low Tom 1";
  case 44:
    return "Pedal Hi-hat";
  case 45:
    return "Mid Tom 2";
  case 46:
    return "Open Hi-hat";
  case 47:
    return "Mid Tom 1";
  case 48:
    return "High Tom 2";
  case 49:
    return "Crash Cymbal 1";
  case 50:
    return "High Tom 1";
  case 51:
    return "Ride Cymbal 1";
  case 52:
    return "Chinese Cymbal";
  case 53:
    return "Ride Bell";
  case 54:
    return "Tambourine";
  case 55:
    return "Splash Cymbal";
  case 56:
    return "Cowbell";
  case 57:
    return "Crash Cymbal 2";
  case 58:
    return "Vibra Slap";
  case 59:
    return "Ride Cymbal 2";
  case 60:
    return "High Bongo";
  case 61:
    return "Low Bongo";
  case 62:
    return "Mute High Conga";
  case 63:
    return "Open High Conga";
  case 64:
    return "Low Conga";
  case 65:
    return "High Timbale";
  case 66:
    return "Low Timbale";
  case 67:
    return "High Agogô";
  case 68:
    return "Low Agogô";
  case 69:
    return "Cabasa";
  case 70:
    return "Maracas";
  case 71:
    return "Short Whistle";
  case 72:
    return "Long Whistle";
  case 73:
    return "Short Güiro";
  case 74:
    return "Long Güiro";
  case 75:
    return "Claves";
  case 76:
    return "High Wood Block";
  case 77:
    return "Low Wood Block";
  case 78:
    return "Mute Cuíca";
  case 79:
    return "Open Cuíca";
  case 80:
    return "Mute Triangle";
  case 81:
    return "Open Triangle";
  default:
    return text(inst);
  }
}
unittest{
  assert (gmName(79) == "Open Cuíca");
  assert (gmName(29) == "29");
  assert (gmName(74) == "Long Güiro");
}
