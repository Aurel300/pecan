package pecan.internal;

#if macro

enum CfgKind {
  Sync;
  Suspend;
  If;
  Accept;
  Yield;
  Label(label:String);
}

#end
