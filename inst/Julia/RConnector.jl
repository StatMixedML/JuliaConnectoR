module RConnector

using Sockets

const TYPE_ID_NOTHING = 0x00
const TYPE_ID_FLOAT64 = 0x01
const TYPE_ID_INT = 0x02
const TYPE_ID_BOOL = 0x03
const TYPE_ID_STRING = 0x04
const TYPE_ID_LIST = 0x05
const TYPE_ID_FAIL = 0xff

const CALL_INDICATOR = 0x01
const RESULT_INDICATOR = 0x00
const BYEBYE = 0xbb

include("reading.jl")
include("evaluating.jl")
include("writing.jl")

function serve(port::Int)
   server = listen(port)
   sock = accept(server)
   println("Julia is listening on port $port.")
   while isopen(sock)
      call = Call()
      try
         firstbyte = read(sock, 1)[1]
         if firstbyte == CALL_INDICATOR
            # Parse incoming function call
            call = read_call(sock)
         elseif firstbyte == BYEBYE
            close(sock)
            return
         end
      catch ex
         error("Unexpected parsing error. Stopping listening. " *
               "Original error: $ex")
      end

      fails = collectfails(call)
      if isempty(fails)
         # evaluate function only if the parsing was totally successful
         result = evaluate!(call)
      else
         result = Fail("Parsing failed. Reason: " * string(fails))
      end

      write(sock, RESULT_INDICATOR)
      writeElement(sock, result)
   end
end

""" Lists the content of a package for import in R"""
function pkgContentList(pkgname::AbstractString; all::Bool = false)
   themodule = RConnector.maineval(pkgname)::Module

   function iscallable(sym::Symbol)
      field = themodule.eval(sym)
      field isa Function || field isa DataType
   end

   function bangfuns_removed(funs::AbstractVector{String})
      ret = Vector{String}()
      sizehint!(ret, length(funs))
      push!(ret, funs[1])
      for i in 2:length(funs)
         # assumes that funs is a sorted vector of strings
         if !(funs[i][end] == '!' && funs[i-1] == funs[i][1:(end-1)])
            push!(ret, funs[i])
         end
      end
      ret
   end

   exportedsyms = names(themodule, all = false)
   exportedfunctions = map(string, filter(iscallable, exportedsyms))
   exportedfunctions = bangfuns_removed(exportedfunctions)

   if all
      allsyms = names(themodule, all = true)
      filter!(sym -> string(sym)[1] != '#', allsyms)
      exportedSymSet = Set(exportedsyms)
      internalsyms = filter(sym -> !(sym in exportedSymSet), allsyms)
      internalfunctions = map(string, filter(iscallable, internalsyms))
      internalfunctions = bangfuns_removed(internalfunctions)
      return ElementList(Vector{Any}(), [:exportedFunctions, :internalFunctions],
            Dict{Symbol, Any}(
                  :exportedFunctions => exportedfunctions,
                  :internalFunctions => internalfunctions))
   else
      return ElementList(Vector{Any}(), [:exportedFunctions],
            Dict{Symbol, Any}(:exportedFunctions => exportedfunctions))
   end
end

end